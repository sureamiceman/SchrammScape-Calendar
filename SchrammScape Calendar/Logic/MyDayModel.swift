//
//  MyDayModel.swift
//  SchrammScape Calendar
//
//  State for the My Day tab: today's job records, map geocoding,
//  check-in / complete time tracking, and duration feedback.
//

import Foundation
import SwiftData
import MapKit
import EventKit

/// Feedback shown after completing a job: actual vs planned duration.
struct DurationFeedback: Identifiable {
    let id = UUID()
    let record: WorkRecord
    let actualMinutes: Int
    let plannedMinutes: Int?

    var differenceMinutes: Int? {
        guard let planned = plannedMinutes else { return nil }
        return actualMinutes - planned
    }
}

@MainActor
@Observable
final class MyDayModel {
    var dayStarted = false
    var records: [WorkRecord] = []
    var feedback: DurationFeedback?
    var statusMessage = ""

    func startDay(context: ModelContext) {
        loadToday(context: context)
        dayStarted = true
        Task {
            await geocodeMissing(context: context)
            // Arm the arrival fences once coordinates are in place.
            await JobAlertService.shared.requestAuthorization()
            JobAlertService.shared.syncArrivalAlerts(records: records)
        }
    }

    func loadToday(context: ModelContext) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.scheduledStart >= dayStart && $0.scheduledStart < dayEnd },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        records = (try? context.fetch(descriptor)) ?? []
        if pruneDeletedCalendarJobs(context: context) {
            records = (try? context.fetch(descriptor)) ?? []
        }
    }

    /// Removes open jobs whose calendar event was deleted (in the app's event
    /// editor or the Calendar app), so My Day mirrors the calendar. Completed
    /// jobs are kept — billing history must survive event deletion.
    private func pruneDeletedCalendarJobs(context: ModelContext) -> Bool {
        // Without calendar access every lookup returns nil; don't wipe the day.
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return false }
        var pruned = false
        for record in records
        where record.statusValue == .scheduled || record.statusValue == .inProgress {
            guard let eventId = record.eventIdentifier,
                  CalendarService.shared.ekEvent(identifier: eventId) == nil else { continue }
            JobAlertService.shared.cancelAlerts(record: record)
            SyncEngine.shared.softDeleteRemote(table: "work_records", id: record.remoteID)
            context.delete(record)
            pruned = true
        }
        if pruned { try? context.save() }
        return pruned
    }

    /// Geocodes any record missing coordinates, caching results on the record.
    func geocodeMissing(context: ModelContext) async {
        for record in records where record.latitude == nil && !record.address.isEmpty {
            guard let location = await GeocodingService.geocode(record.address) else {
                // Leave the pin off the map; directions can still open by address.
                continue
            }
            record.latitude = location.coordinate.latitude
            record.longitude = location.coordinate.longitude
        }
        try? context.save()
    }

    func checkIn(_ record: WorkRecord, context: ModelContext) {
        record.actualStart = .now
        record.statusValue = .inProgress
        record.markDirty()
        try? context.save()
        Task { await SyncEngine.shared.syncNow() }
        // Swap the arrival fence for a departure fence.
        JobAlertService.shared.cancelAlerts(record: record)
        JobAlertService.shared.scheduleDepartureAlert(record: record)
    }

    func complete(_ record: WorkRecord, context: ModelContext) {
        if record.actualStart == nil {
            // Completed without a check-in: assume the scheduled start.
            record.actualStart = record.scheduledStart
        }
        record.actualEnd = .now
        record.statusValue = .completed
        record.markDirty()
        try? context.save()
        JobAlertService.shared.cancelAlerts(record: record)
        Task {
            await MileageLogger.logLeg(to: record, context: context)
            await SyncEngine.shared.syncNow()
        }
        if let actual = record.actualDurationMinutes {
            feedback = DurationFeedback(
                record: record,
                actualMinutes: actual,
                plannedMinutes: record.plannedDurationMinutes
            )
        }
    }

    /// Saves the measured duration as the customer's new default.
    func updateCustomerDuration(_ record: WorkRecord, minutes: Int, context: ModelContext) {
        let name = record.customerName
        let descriptor = FetchDescriptor<Customer>(predicate: #Predicate { $0.name == name })
        guard let customer = try? context.fetch(descriptor).first else {
            statusMessage = "No customer named \(name) found to update."
            return
        }
        customer.durationLabel = String(minutes)
        customer.markDirty()
        try? context.save()
        statusMessage = "\(name)'s default duration updated to \(minutes) min."
    }

    // MARK: - Day plan

    /// Total planned work minutes today; falls back to the scheduled window
    /// when a job has no stored duration.
    var totalPlannedMinutes: Int {
        records.reduce(0) { total, record in
            let planned = record.plannedDurationMinutes
                ?? Int(record.scheduledEnd.timeIntervalSince(record.scheduledStart) / 60)
            return total + max(0, planned)
        }
    }

    /// Minutes as "H:MM", e.g. 375 → "6:15".
    static func hhmm(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "8 jobs today — 6:15 of planned work"
    var dayPlanSummary: String {
        guard !records.isEmpty else { return "" }
        let jobs = "\(records.count) job\(records.count == 1 ? "" : "s") today"
        return "\(jobs) — \(Self.hhmm(totalPlannedMinutes)) of planned work"
    }

    // MARK: - Progress

    var completedCount: Int {
        records.filter { $0.statusValue == .completed }.count
    }

    /// Positive = running ahead of schedule, negative = behind.
    var minutesAheadOfSchedule: Int {
        records.filter { $0.statusValue == .completed }.reduce(0) { total, record in
            guard let actual = record.actualDurationMinutes,
                  let planned = record.plannedDurationMinutes else { return total }
            return total + (planned - actual)
        }
    }

    var progressSummary: String {
        guard !records.isEmpty else { return "" }
        var text = "\(completedCount) of \(records.count) jobs done"
        let delta = minutesAheadOfSchedule
        if completedCount > 0, delta != 0 {
            text += delta > 0
                ? ", running \(delta) min ahead"
                : ", running \(-delta) min behind"
        }
        return text
    }
}
