//
//  MileageEntry.swift
//  SchrammScape Calendar
//
//  One logged business-driving leg (previous stop → completed job), using
//  real road distances from Apple's directions. Feeds the tax mileage
//  summaries in the Billing tab.
//

import Foundation
import SwiftData

@Model
final class MileageEntry {
    var date: Date = Date.now
    var fromLabel: String = ""
    var toLabel: String = ""
    var miles: Double = 0
    /// The completed job this leg arrived at (one entry per job).
    var eventIdentifier: String?
    var createdAt: Date = Date.now
    // Sync metadata (Supabase).
    var remoteID: UUID = UUID()
    var syncedAt: Date?
    var isDirty: Bool = true

    init(
        date: Date = .now,
        fromLabel: String = "",
        toLabel: String = "",
        miles: Double = 0,
        eventIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.date = date
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.miles = miles
        self.eventIdentifier = eventIdentifier
        self.createdAt = createdAt
    }
}
