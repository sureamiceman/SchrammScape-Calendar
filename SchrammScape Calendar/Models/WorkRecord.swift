//
//  WorkRecord.swift
//  SchrammScape Calendar
//
//  A persistent record of a scheduled/completed job visit. Created when jobs
//  are sent to the calendar; drives the My Day flow and the Work Log.
//  Customer info is denormalized so history survives customer edits/deletes.
//

import Foundation
import SwiftData

@Model
final class WorkRecord {
    var customerName: String
    var address: String
    var jobTitle: String
    var phone: String
    var notes: String
    var scheduledStart: Date
    var scheduledEnd: Date
    var actualStart: Date?
    var actualEnd: Date?
    var status: String = Status.scheduled.rawValue
    var plannedDurationMinutes: Int?
    /// Names of add-on services included in this visit (drives per-visit rotations).
    var servicesPerformed: [String] = []
    /// Jobs added on the spot during the visit (billed as extra lines).
    var extraServices: [String] = []
    /// Free-form note about extra work done beyond the title (shown on invoices).
    var extraNotes: String = ""
    /// Set when this visit is billed on an invoice (prevents double-billing).
    var invoiceNumber: String?
    var eventIdentifier: String?
    // Geocode cache for the My Day map.
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    enum Status: String {
        case scheduled
        case inProgress
        case completed
        case skipped
    }

    init(
        customerName: String = "",
        address: String = "",
        jobTitle: String = "",
        phone: String = "",
        notes: String = "",
        scheduledStart: Date = .now,
        scheduledEnd: Date = .now,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        status: Status = .scheduled,
        plannedDurationMinutes: Int? = nil,
        eventIdentifier: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = .now
    ) {
        self.customerName = customerName
        self.address = address
        self.jobTitle = jobTitle
        self.phone = phone
        self.notes = notes
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.status = status.rawValue
        self.plannedDurationMinutes = plannedDurationMinutes
        self.eventIdentifier = eventIdentifier
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }

    var statusValue: Status {
        get { Status(rawValue: status) ?? .scheduled }
        set { status = newValue.rawValue }
    }

    /// Minutes between check-in and completion, when both exist.
    var actualDurationMinutes: Int? {
        guard let start = actualStart, let end = actualEnd, end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }
}
