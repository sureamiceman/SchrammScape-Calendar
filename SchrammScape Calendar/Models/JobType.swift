//
//  JobType.swift
//  SchrammScape Calendar
//
//  The global catalog of job/service types the business offers.
//  "Mow, Edge and Blowoff" is the default base service; the user can add
//  others (Mulch Spreading, Bush Trimming and Cleanup, …) in the Jobs tab.
//

import Foundation
import SwiftData

@Model
final class JobType {
    // CloudKit sync requires inline defaults (or optionals) on all stored properties.
    var name: String = ""
    var defaultDurationMinutes: Int = 30
    /// True for the standard base service applied to routine visits.
    var isDefault: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(
        name: String = "",
        defaultDurationMinutes: Int = 30,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.name = name
        self.defaultDurationMinutes = defaultDurationMinutes
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
