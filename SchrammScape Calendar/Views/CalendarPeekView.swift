//
//  CalendarPeekView.swift
//  SchrammScape Calendar
//
//  What's already on the device calendar for a chosen day. Tap an event to
//  edit it (times, title, delete) in the system event editor.
//

import SwiftUI
import EventKit
import EventKitUI

struct CalendarPeekView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var events: [ExistingEvent] = []
    @State private var accessDenied = false
    @State private var editTarget: EditTarget?

    private struct EditTarget: Identifiable {
        let id = UUID()
        let event: EKEvent
    }

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
                            Button {
                                edit(event)
                            } label: {
                                eventRow(event)
                            }
                            .tint(.primary)
                            .disabled(!event.isEditable)
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
            .sheet(item: $editTarget) { target in
                EventEditView(event: target.event) {
                    editTarget = nil
                    Task { await reload() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func eventRow(_ event: ExistingEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text("\(TimeSlot.display(event.start)) – \(TimeSlot.display(event.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if event.isEditable {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func edit(_ event: ExistingEvent) {
        guard let identifier = event.eventIdentifier,
              let ekEvent = CalendarService.shared.ekEvent(identifier: identifier) else { return }
        editTarget = EditTarget(event: ekEvent)
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

// MARK: - System event editor wrapper

private struct EventEditView: UIViewControllerRepresentable {
    let event: EKEvent
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = CalendarService.shared.eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onDone()
        }
    }
}
