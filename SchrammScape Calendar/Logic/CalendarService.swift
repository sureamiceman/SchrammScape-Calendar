//
//  CalendarService.swift
//  SchrammScape Calendar
//
//  EventKit wrapper replacing the web app's Google Calendar REST flow.
//  Creates, updates, and removes events on the device's default calendar
//  (which syncs to Google if a Google account is added in iOS Settings).
//

import EventKit

/// A snapshot of an event already on the user's calendar.
struct ExistingEvent: Identifiable {
    let id: String
    let eventIdentifier: String?
    let title: String
    let location: String
    let start: Date
    let end: Date
    let calendarTitle: String
    let isEditable: Bool
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

    // MARK: - Calendar selection

    /// User-chosen target calendar; "" / unknown falls back to the system default.
    static let selectedCalendarKey = "selectedCalendarID"

    /// All calendars the app could write events to.
    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The calendar new events go to: the user's selection if it still exists
    /// and is writable, otherwise the system default.
    var targetCalendar: EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: Self.selectedCalendarKey),
           !id.isEmpty,
           let calendar = store.calendar(withIdentifier: id),
           calendar.allowsContentModifications {
            return calendar
        }
        return store.defaultCalendarForNewEvents
    }

    /// Creates a new event or updates the existing one, returning its identifier.
    @discardableResult
    func save(_ event: ScheduledEvent, existingIdentifier: String?) throws -> String {
        let ekEvent: EKEvent
        if let id = existingIdentifier, let found = store.event(withIdentifier: id) {
            ekEvent = found
        } else {
            ekEvent = EKEvent(eventStore: store)
            guard let calendar = targetCalendar else {
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
                    eventIdentifier: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    location: event.location ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    calendarTitle: event.calendar?.title ?? "",
                    isEditable: event.calendar?.allowsContentModifications ?? false
                )
            }
    }

    /// The underlying store — required by the system event-edit UI, which must
    /// share the store instance of the event being edited.
    var eventStore: EKEventStore { store }

    func ekEvent(identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }

    func remove(identifier: String) throws {
        guard let ekEvent = store.event(withIdentifier: identifier) else { return }
        try store.remove(ekEvent, span: .thisEvent, commit: true)
    }
}
