//
//  Customer.swift
//  SchrammScape Calendar
//
//  Reference customer, ported from the web app's `reference_customers` table.
//

import Foundation
import SwiftData

@Model
final class Customer {
    var name: String
    var address: String
    var jobTitle: String
    var durationLabel: String
    var sortOrder: Int
    var createdAt: Date
    // Extended fields from the Supabase customer table.
    var dayOfWeek: String = ""   // MON, TUE, WED, THU, FRI ("" = unassigned)
    var mower: String = ""       // e.g. "42", "PUSH", "42+PUSH"
    var details: String = ""     // job notes
    var phone: String = ""
    var email: String = ""
    var height: String = ""      // cutting height, e.g. "3.5"
    // Address validation: coordinates confirmed by Maps geocoding.
    var latitude: Double?
    var longitude: Double?
    var geocodeStatus: String = ""  // "" = unvalidated, "valid", "failed"
    /// Visit cadence in calendar weeks: 1 = weekly, 2 = bi-weekly.
    var visitIntervalWeeks: Int = 1
    /// Add-on services (weeding, edging, …) on their own per-visit rotations.
    @Relationship(deleteRule: .cascade, inverse: \ServiceItem.customer)
    var services: [ServiceItem] = []

    enum GeocodeStatus: String {
        case unvalidated = ""
        case valid
        case failed
    }

    init(
        name: String = "",
        address: String = "",
        jobTitle: String = "",
        durationLabel: String = "",
        sortOrder: Int = 0,
        createdAt: Date = .now,
        dayOfWeek: String = "",
        mower: String = "",
        details: String = "",
        phone: String = "",
        email: String = "",
        height: String = "",
        visitIntervalWeeks: Int = 1
    ) {
        self.name = name
        self.address = address
        self.jobTitle = jobTitle
        self.durationLabel = durationLabel
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.dayOfWeek = dayOfWeek
        self.mower = mower
        self.details = details
        self.phone = phone
        self.email = email
        self.height = height
        self.visitIntervalWeeks = visitIntervalWeeks
    }

    var geocodeStatusValue: GeocodeStatus {
        get { GeocodeStatus(rawValue: geocodeStatus) ?? .unvalidated }
        set { geocodeStatus = newValue.rawValue }
    }

    /// Clears validation when the address changes so stale coordinates aren't trusted.
    func invalidateGeocode() {
        latitude = nil
        longitude = nil
        geocodeStatusValue = .unvalidated
    }

    /// Parsed duration in minutes, or nil for blank / "TBD".
    var durationMinutes: Int? { TimeSlot.parseDurationMinutes(durationLabel) }

    /// The base service part of the job title, e.g. "Mowing" from "Mowing Joel Morrow".
    /// Used when composing multi-service titles like "Mowing + Weeding — Joel Morrow".
    var baseServiceLabel: String {
        guard !name.isEmpty, jobTitle.localizedCaseInsensitiveContains(name) else { return jobTitle }
        let stripped = jobTitle
            .replacingOccurrences(of: name, with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? jobTitle : stripped
    }

    /// Sorted, active add-on services.
    var sortedServices: [ServiceItem] {
        services.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Matches the web app's customer picker label: "Name - Address".
    var optionLabel: String {
        [name.isEmpty ? jobTitle : name, address]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}
