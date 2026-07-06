//
//  CalendarService.swift
//  SchrammScape Calendar
//
//  EventKit wrapper replacing the web app's Google Calendar REST flow.
//  Creates, updates, and removes events on the device's default calendar
//  (which syncs to Google if a Google account is added in iOS Settings).
//

import EventKit

/// A read-only snapshot of an event already on the user's calendar.
struct ExistingEvent: Identifiable {
    let id: String
    let title: String
    let location: String
    let start: Date
    let end: Date
    let calendarTitle: String
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    enum CalendarError: LocalizedError {
        case noDefaultCalendar
        var errorDescription: String? {
            switch self {
            case .noDefaultCalendar:
                return "No default calendar is available to add events to. Add one in the Calendar app first."
            }
        }
    }

    /// Requests full access (needed so we can read our own events back to update/delete them).
    func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    /// Creates a new event or updates the existing one, returning its identifier.
    @discardableResult
    func save(_ event: ScheduledEvent, existingIdentifier: String?) throws -> String {
        let ekEvent: EKEvent
        if let id = existingIdentifier, let found = store.event(withIdentifier: id) {
            ekEvent = found
        } else {
            ekEvent = EKEvent(eventStore: store)
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalendarError.noDefaultCalendar
            }
            ekEvent.calendar = calendar
        }
        ekEvent.title = event.title
        ekEvent.location = event.location.isEmpty ? nil : event.location
        ekEvent.notes = event.notes.isEmpty ? nil : event.notes
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        try store.save(ekEvent, span: .thisEvent, commit: true)
        return ekEvent.eventIdentifier
    }

    /// Returns everything already scheduled on the given day, sorted by start time.
    func events(on day: Date) -> [ExistingEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                ExistingEvent(
                    // Recurring events share an identifier, so include the start time for uniqueness.
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    location: event.location ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    calendarTitle: event.calendar?.title ?? ""
                )
            }
    }

    func remove(identifier: String) throws {
        guard let ekEvent = store.event(withIdentifier: identifier) else { return }
        try store.remove(ekEvent, span: .thisEvent, commit: true)
    }
}
