//
//  JobAlertService.swift
//  SchrammScape Calendar
//
//  GPS arrival/departure prompts via system-monitored location notifications
//  (UNLocationNotificationTrigger). Arriving at a scheduled job asks the user
//  to check in; leaving a job with the timer running asks to mark it complete.
//  Notification-driven completion just toggles state — no duration feedback,
//  no comments or extra jobs (the user presumably forgot to close it out).
//

import Foundation
import SwiftData
import CoreLocation
import UserNotifications

@MainActor
final class JobAlertService: NSObject {
    static let shared = JobAlertService()

    private var container: ModelContainer?
    private let center = UNUserNotificationCenter.current()

    private static let arrivalCategory = "JOB_ARRIVAL"
    private static let departureCategory = "JOB_DEPARTURE"
    private static let checkInAction = "CHECK_IN"
    private static let completeAction = "MARK_COMPLETE"
    private static let regionRadius: CLLocationDistance = 150

    /// Call once at app launch: wires the notification delegate and categories.
    func setUp(container: ModelContainer) {
        self.container = container
        center.delegate = self

        let checkIn = UNNotificationAction(
            identifier: Self.checkInAction,
            title: "Check In",
            options: []
        )
        let complete = UNNotificationAction(
            identifier: Self.completeAction,
            title: "Mark Complete",
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.arrivalCategory, actions: [checkIn], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.departureCategory, actions: [complete], intentIdentifiers: [])
        ])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Scheduling

    /// Replaces all pending arrival fences with ones for today's scheduled jobs.
    func syncArrivalAlerts(records: [WorkRecord]) {
        let calendar = Calendar.current
        let todaysScheduled = records.filter {
            calendar.isDateInToday($0.scheduledStart) && $0.statusValue == .scheduled
        }
        // Clear every pending job alert, then rebuild arrival fences.
        center.getPendingNotificationRequests { [weak self] pending in
            let jobAlertIDs = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("arrive-") || $0.hasPrefix("depart-") }
            Task { @MainActor in
                guard let self else { return }
                self.center.removePendingNotificationRequests(withIdentifiers: jobAlertIDs)
                for record in todaysScheduled {
                    self.scheduleArrivalAlert(record: record)
                }
            }
        }
    }

    /// Re-syncs arrival fences from whatever is scheduled today in the store
    /// (used after scheduling or replanning changes today's lineup).
    func syncTodayAlerts(context: ModelContext) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.scheduledStart >= dayStart && $0.scheduledStart < dayEnd }
        )
        syncArrivalAlerts(records: (try? context.fetch(descriptor)) ?? [])
    }

    func scheduleArrivalAlert(record: WorkRecord) {
        guard let request = locationRequest(
            record: record,
            idPrefix: "arrive-",
            category: Self.arrivalCategory,
            title: "You've arrived at \(record.jobTitle)",
            body: "Check in and get started?",
            onEntry: true
        ) else { return }
        center.add(request)
    }

    func scheduleDepartureAlert(record: WorkRecord) {
        guard let request = locationRequest(
            record: record,
            idPrefix: "depart-",
            category: Self.departureCategory,
            title: "Looks like you're done with \(record.jobTitle)",
            body: "Mark it as Complete?",
            onEntry: false
        ) else { return }
        center.add(request)
    }

    func cancelAlerts(record: WorkRecord) {
        guard let eventID = record.eventIdentifier else { return }
        center.removePendingNotificationRequests(withIdentifiers: ["arrive-\(eventID)", "depart-\(eventID)"])
    }

    private func locationRequest(
        record: WorkRecord,
        idPrefix: String,
        category: String,
        title: String,
        body: String,
        onEntry: Bool
    ) -> UNNotificationRequest? {
        guard let eventID = record.eventIdentifier,
              let lat = record.latitude, let lon = record.longitude else { return nil }

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            radius: Self.regionRadius,
            identifier: "\(idPrefix)\(eventID)"
        )
        region.notifyOnEntry = onEntry
        region.notifyOnExit = !onEntry

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["eventID": eventID]

        return UNNotificationRequest(
            identifier: "\(idPrefix)\(eventID)",
            content: content,
            trigger: UNLocationNotificationTrigger(region: region, repeats: false)
        )
    }

    // MARK: - Handling taps/actions

    private func record(forEventID eventID: String) -> WorkRecord? {
        guard let context = container?.mainContext else { return nil }
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.eventIdentifier == eventID }
        )
        return try? context.fetch(descriptor).first
    }

    private func handleArrival(eventID: String) {
        guard let record = record(forEventID: eventID),
              record.statusValue == .scheduled else { return }
        record.actualStart = .now
        record.statusValue = .inProgress
        try? container?.mainContext.save()
        scheduleDepartureAlert(record: record)
    }

    /// Quiet completion: toggles the state only — no duration feedback,
    /// no extras. The default duration stays untouched.
    private func handleDeparture(eventID: String) {
        guard let record = record(forEventID: eventID),
              record.statusValue == .inProgress else { return }
        if record.actualStart == nil {
            record.actualStart = record.scheduledStart
        }
        record.actualEnd = .now
        record.statusValue = .completed
        try? container?.mainContext.save()
        cancelAlerts(record: record)
        if let context = container?.mainContext {
            Task { await MileageLogger.logLeg(to: record, context: context) }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension JobAlertService: UNUserNotificationCenterDelegate {

    /// Show the prompt as a banner even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard let eventID = content.userInfo["eventID"] as? String else { return }
        let category = content.categoryIdentifier
        let action = response.actionIdentifier

        await MainActor.run {
            switch (category, action) {
            case (Self.arrivalCategory, Self.checkInAction),
                 (Self.arrivalCategory, UNNotificationDefaultActionIdentifier):
                JobAlertService.shared.handleArrival(eventID: eventID)
            case (Self.departureCategory, Self.completeAction),
                 (Self.departureCategory, UNNotificationDefaultActionIdentifier):
                JobAlertService.shared.handleDeparture(eventID: eventID)
            default:
                break
            }
        }
    }
}
