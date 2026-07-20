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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [WorkRecord]
    @State private var supabase = SupabaseService.shared
    @State private var restoredSession = false

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
        Group {
            if supabase.isSignedIn {
                tabs
            } else if restoredSession {
                LoginView()
            } else {
                ProgressView()
            }
        }
        .task {
            SeedData.seedIfNeeded(context)
            await supabase.restoreSession()
            restoredSession = true
            await SyncEngine.shared.syncNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SyncEngine.shared.syncNow() }
            }
        }
    }

    private var tabs: some View {
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Customer.self, inMemory: true)
}
