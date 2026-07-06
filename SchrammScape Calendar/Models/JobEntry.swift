//
//  JobEntry.swift
//  SchrammScape Calendar
//
//  In-editor job (a "job card" in the web app) and the resolved calendar event.
//

import Foundation

/// An add-on service choice carried on a job in the review step.
struct AddOnOption: Identifiable {
    var id: String { name }
    let name: String
    let durationMinutes: Int
    var included: Bool
}

/// A single editable row in the Schedule Builder.
struct JobEntry: Identifiable {
    let id = UUID()
    var customerLabel: String = ""
    var customerName: String = ""
    var title: String = ""
    var location: String = ""
    var day: Date = Calendar.current.startOfDay(for: .now)
    var start: String = ""   // "HH:mm"
    var end: String = ""     // "HH:mm"
    var notes: String = ""
    var phone: String = ""
    var durationMinutes: Int? = nil
    /// True when the duration is a placeholder because the customer's is blank/TBD.
    var estimatedDuration: Bool = false
    /// Add-on services available at this stop; `included` ones count toward
    /// the title, duration, and the visit's servicesPerformed record.
    var addOnOptions: [AddOnOption] = []
    // Base pieces kept so toggling add-ons can recompose title and duration.
    var baseTitle: String = ""          // e.g. "Mowing Joel Morrow"
    var baseServiceLabel: String = ""   // e.g. "Mowing"
    var baseDurationMinutes: Int = 0
    var eventIdentifier: String? = nil
    // Validated coordinates carried over from the customer record.
    var latitude: Double? = nil
    var longitude: Double? = nil

    var isEmpty: Bool {
        title.isEmpty && location.isEmpty && start.isEmpty && end.isEmpty && notes.isEmpty
    }
}

/// A job resolved to concrete start/end dates, ready for EventKit or `.ics`.
struct ScheduledEvent: Sendable {
    var title: String
    var location: String
    var notes: String
    var start: Date
    var end: Date
}
