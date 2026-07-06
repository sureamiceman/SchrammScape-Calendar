//
//  SeedData.swift
//  SchrammScape Calendar
//
//  Seeds the default customer list into SwiftData on first launch.
//

import Foundation
import SwiftData

enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Customer>())) ?? 0
        if count == 0 {
            for (index, parsed) in DefaultCustomers.all.enumerated() {
                context.insert(parsed.makeCustomer(sortOrder: index))
            }
        }
        seedJobTypesIfNeeded(context)
        try? context.save()
    }

    /// Seeds the starter job catalog; the user manages it in the Jobs tab.
    @MainActor
    private static func seedJobTypesIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<JobType>())) ?? 0
        guard count == 0 else { return }
        let starters: [(String, Int, Bool)] = [
            ("Mow, Edge and Blowoff", 45, true),
            ("Mulch Spreading", 60, false),
            ("Bush Trimming and Cleanup", 45, false),
            ("Apply River Rock", 90, false)
        ]
        for (index, starter) in starters.enumerated() {
            context.insert(JobType(
                name: starter.0,
                defaultDurationMinutes: starter.1,
                isDefault: starter.2,
                sortOrder: index
            ))
        }
    }
}
