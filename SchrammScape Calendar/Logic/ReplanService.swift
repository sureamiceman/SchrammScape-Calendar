//
//  ReplanService.swift
//  SchrammScape Calendar
//
//  Weather replanning: moves scheduled WorkRecords between days ("push" out
//  / "pull" forward), re-optimizes the affected days' routes with real drive
//  times, and keeps the device calendar events in sync.
//

import Foundation
import SwiftData
import CoreLocation

@MainActor
enum ReplanService {

    /// Moves records to another day, then re-optimizes both the target day
    /// and what remains of the source day. Returns a status line.
    static func moveRecords(
        _ records: [WorkRecord],
        toDay targetDay: Date,
        context: ModelContext
    ) async -> String {
        guard !records.isEmpty else { return "No jobs selected." }
        let calendar = Calendar.current
        let sourceDays = Set(records.map { calendar.startOfDay(for: $0.scheduledStart) })
        let target = calendar.startOfDay(for: targetDay)

        // Shift each record's date, preserving its duration and resetting
        // any in-progress state (a pushed job starts over on the new day).
        for record in records {
            let duration = record.plannedDurationMinutes
                ?? max(15, Int(record.scheduledEnd.timeIntervalSince(record.scheduledStart) / 60))
            let time = calendar.dateComponents([.hour, .minute], from: record.scheduledStart)
            let newStart = calendar.date(
                bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: target
            ) ?? target
            record.scheduledStart = newStart
            record.scheduledEnd = newStart.addingTimeInterval(Double(duration) * 60)
            record.statusValue = .scheduled
            record.actualStart = nil
            record.actualEnd = nil
        }

        await reoptimizeDay(target, context: context)
        for day in sourceDays where day != target {
            await reoptimizeDay(day, context: context)
        }
        try? context.save()
        // Jobs may have moved on or off today — rebuild the GPS arrival fences.
        JobAlertService.shared.syncTodayAlerts(context: context)

        let dayLabel = target.formatted(.dateTime.weekday(.abbreviated).month().day())
        let isToday = calendar.isDateInToday(target)
        let count = records.count
        return isToday
            ? "Pulled \(count) job\(count == 1 ? "" : "s") to today; route re-optimized."
            : "Pushed \(count) job\(count == 1 ? "" : "s") to \(dayLabel); routes re-optimized."
    }

    /// Re-optimizes and re-chains all *scheduled* records on the given day,
    /// then updates their calendar events. Completed/in-progress records are
    /// left untouched.
    static func reoptimizeDay(_ day: Date, context: ModelContext) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let scheduled = WorkRecord.Status.scheduled.rawValue
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate {
                $0.scheduledStart >= dayStart && $0.scheduledStart < dayEnd && $0.status == scheduled
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return }

        // Every stop needs coordinates for optimization.
        for record in records where record.latitude == nil && !record.address.isEmpty {
            if let location = await GeocodingService.geocode(record.address) {
                record.latitude = location.coordinate.latitude
                record.longitude = location.coordinate.longitude
            }
        }

        // Anchor point: current location; fall back to the first stop.
        var anchor: CLLocationCoordinate2D?
        if let current = try? await LocationService.currentLocation() {
            anchor = current.coordinate
        } else if let first = records.first(where: { $0.latitude != nil }),
                  let lat = first.latitude, let lon = first.longitude {
            anchor = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Optimize the visiting order (records without coordinates keep their
        // relative order at the end of the route).
        var ordered = records
        if let anchor, records.count > 1 {
            let pairs = records.compactMap { record -> (id: UUID, record: WorkRecord, stop: RouteOptimizer.Stop)? in
                guard let lat = record.latitude, let lon = record.longitude else { return nil }
                let id = UUID()
                return (id, record, RouteOptimizer.Stop(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }
            if pairs.count > 1 {
                let result = await RouteOptimizer.optimize(from: anchor, stops: pairs.map(\.stop)) { a, b in
                    await DriveTimeService.shared.travelTime(from: a, to: b)
                }
                let recordsByStopID = Dictionary(uniqueKeysWithValues: pairs.map { ($0.id, $0.record) })
                let optimized = result.route.compactMap { recordsByStopID[$0.id] }
                let unlocatable = records.filter { $0.latitude == nil }
                ordered = optimized + unlocatable
            }
        }

        // Chain times: anchor time, then each next start = previous end + drive.
        var cursor = anchorMinutes(for: dayStart, existing: records)
        var previous = anchor
        for (index, record) in ordered.enumerated() {
            if let from = previous, let lat = record.latitude, let lon = record.longitude {
                let to = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let seconds = await DriveTimeService.shared.travelTime(from: from, to: to)
                let driveMinutes = max(5, Int((seconds / 60 / 5).rounded(.up)) * 5)
                // The first stop begins at the anchor time; its leg is travel-to-start.
                if index > 0 { cursor += driveMinutes }
            }
            let duration = record.plannedDurationMinutes
                ?? max(15, Int(record.scheduledEnd.timeIntervalSince(record.scheduledStart) / 60))
            record.scheduledStart = TimeSlot.date(day: dayStart, hhmm: TimeSlot.string(fromMinutes: cursor))
                ?? record.scheduledStart
            cursor += duration
            record.scheduledEnd = TimeSlot.date(day: dayStart, hhmm: TimeSlot.string(fromMinutes: cursor))
                ?? record.scheduledEnd
            if let lat = record.latitude, let lon = record.longitude {
                previous = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }

        syncCalendar(for: ordered)
        try? context.save()
    }

    /// Start-of-route time in minutes: today → now rounded up to the next
    /// 15-minute slot; a future day → its earliest already-planned start, else 8:00 AM.
    private static func anchorMinutes(for dayStart: Date, existing: [WorkRecord]) -> Int {
        let calendar = Calendar.current
        if calendar.isDateInToday(dayStart) {
            let now = Date.now
            let mins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let rounded = Int((Double(mins) / Double(TimeSlot.increment)).rounded(.up)) * TimeSlot.increment
            return min(max(rounded, TimeSlot.startMinutes), TimeSlot.maxStartMinutes)
        }
        if let earliest = existing.map(\.scheduledStart).min() {
            let mins = calendar.component(.hour, from: earliest) * 60 + calendar.component(.minute, from: earliest)
            return min(max(mins, TimeSlot.startMinutes), TimeSlot.maxStartMinutes)
        }
        return 8 * 60
    }

    /// Pushes each record's new times into its existing calendar event.
    private static func syncCalendar(for records: [WorkRecord]) {
        for record in records {
            guard let eventId = record.eventIdentifier else { continue }
            let event = ScheduledEvent(
                title: record.jobTitle,
                location: record.address,
                notes: record.notes,
                start: record.scheduledStart,
                end: record.scheduledEnd
            )
            record.eventIdentifier = try? CalendarService.shared.save(event, existingIdentifier: eventId)
        }
    }
}
