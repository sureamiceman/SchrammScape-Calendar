//
//  ContentView.swift
//  SchrammScape Calendar
//
//  Created by Tim Schramm on 7/1/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [WorkRecord]

    /// Jobs scheduled for today that aren't finished yet — shown as the My Day badge.
    private var todaysOpenJobCount: Int {
        let calendar = Calendar.current
        return records.filter { record in
            calendar.isDateInToday(record.scheduledStart)
                && record.statusValue != .completed
                && record.statusValue != .skipped
        }.count
    }

    var body: some View {
        TabView {
            ScheduleBuilderView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            CustomersView()
                .tabItem { Label("Customers", systemImage: "person.2") }
            JobsView()
                .tabItem { Label("Jobs", systemImage: "wrench.and.screwdriver") }
            MyDayView()
                .tabItem { Label("My Day", systemImage: "sun.max") }
                .badge(todaysOpenJobCount)
            WorkLogView()
                .tabItem { Label("Billing", systemImage: "checklist") }
        }
        .task {
            SeedData.seedIfNeeded(context)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Customer.self, inMemory: true)
}
