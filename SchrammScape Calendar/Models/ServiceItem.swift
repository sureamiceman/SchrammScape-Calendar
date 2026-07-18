//
//  ServiceItem.swift
//  SchrammScape Calendar
//
//  An add-on service for a customer (e.g. "Weeding flower beds") that
//  recurs on a per-visit rotation: every visit, every 2nd visit, etc.
//

import Foundation
import SwiftData

@Model
final class ServiceItem {
    // CloudKit sync requires inline defaults (or optionals) on all stored properties.
    var name: String = ""
    var durationMinutes: Int = 15
    /// 1 = every visit, 2 = every other visit, 3 = every third visit…
    var intervalVisits: Int = 2
    var sortOrder: Int = 0
    var customer: Customer?

    init(
        name: String = "",
        durationMinutes: Int = 15,
        intervalVisits: Int = 2,
        sortOrder: Int = 0,
        customer: Customer? = nil
    ) {
        self.name = name
        self.durationMinutes = durationMinutes
        self.intervalVisits = intervalVisits
        self.sortOrder = sortOrder
        self.customer = customer
    }

    /// "every visit", "every 2nd visit", …
    var frequencyLabel: String {
        switch intervalVisits {
        case ...1: return "every visit"
        case 2: return "every 2nd visit"
        case 3: return "every 3rd visit"
        default: return "every \(intervalVisits)th visit"
        }
    }
}
