//
//  SchrammScape_CalendarApp.swift
//  SchrammScape Calendar
//
//  Created by Tim Schramm on 7/1/26.
//

import SwiftUI
import SwiftData

@main
struct SchrammScape_CalendarApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Customer.self, WorkRecord.self, ServiceItem.self, JobType.self, Invoice.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        JobAlertService.shared.setUp(container: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
