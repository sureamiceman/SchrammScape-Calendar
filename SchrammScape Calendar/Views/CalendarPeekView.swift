//
//  CalendarPeekView.swift
//  SchrammScape Calendar
//
//  Read-only look at what's already on the device calendar for a chosen day,
//  so the user can see existing commitments before scheduling jobs.
//

import SwiftUI

struct CalendarPeekView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var events: [ExistingEvent] = []
    @State private var accessDenied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section("Already Scheduled") {
                    if accessDenied {
                        Label(
                            "Calendar access was denied. Enable it in Settings › Privacy › Calendars.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                    } else if events.isEmpty {
                        Text("Nothing scheduled for this day.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                Text("\(event.start.formatted(.dateTime.hour().minute())) – \(event.end.formatted(.dateTime.hour().minute()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !event.location.isEmpty {
                                    Text(event.location)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Existing Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: day) { await reload() }
        }
    }

    private func reload() async {
        guard await CalendarService.shared.requestAccess() else {
            accessDenied = true
            events = []
            return
        }
        accessDenied = false
        events = CalendarService.shared.events(on: day)
    }
}
