//
//  ScheduleBuilderView.swift
//  SchrammScape Calendar
//
//  The Schedule tab as a 3-step wizard:
//  1. pick a day & start time  2. select the day's jobs (day-of-week preselected)
//  3. review the drive-time-optimized route, then send to the calendar.
//

import SwiftUI
import SwiftData
import EventKit

struct ScheduleBuilderView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Customer.sortOrder), SortDescriptor(\Customer.createdAt)])
    private var customers: [Customer]

    @State private var model = ScheduleBuilderModel()
    @State private var shareItem: ShareItem?
    @State private var showingCalendarPeek = false
    @State private var notesTarget: NotesTarget?
    @State private var writableCalendars: [EKCalendar] = []
    @AppStorage(CalendarService.selectedCalendarKey) private var selectedCalendarID = ""

    private struct NotesTarget: Identifiable {
        let id: JobEntry.ID
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .pickDay: pickDayStep
                case .selectJobs: selectJobsStep
                case .review: reviewStep
                }
            }
            .navigationTitle(stepTitle)
            .toolbar {
                if model.step != .pickDay {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                    }
                }
                if model.step == .review {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { shareICS() } label: {
                                Label("Share .ics File", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                Task { await model.removeFromCalendar() }
                            } label: {
                                Label("Remove From Calendar", systemImage: "calendar.badge.minus")
                            }
                            Divider()
                            Button(role: .destructive) { model.reset() } label: {
                                Label("Start Over", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .sheet(isPresented: $showingCalendarPeek) {
                CalendarPeekView()
            }
            .sheet(item: $notesTarget) { target in
                NotesEditorView(model: model, jobID: target.id)
            }
        }
    }

    private var stepTitle: String {
        switch model.step {
        case .pickDay: "Schedule"
        case .selectJobs: "Select Jobs"
        case .review: "Review Route"
        }
    }

    private func goBack() {
        switch model.step {
        case .selectJobs: model.step = .pickDay
        case .review: model.step = .selectJobs
        case .pickDay: break
        }
        model.errorMessage = nil
    }

    // MARK: - Step 1: pick day

    private var pickDayStep: some View {
        List {
            Section {
                Button {
                    showingCalendarPeek = true
                } label: {
                    Label("View Existing Calendar", systemImage: "calendar")
                }
                if writableCalendars.isEmpty {
                    Button {
                        Task { await loadCalendars(requestingAccess: true) }
                    } label: {
                        Label("Choose Calendar for Events…", systemImage: "calendar.badge.checkmark")
                    }
                } else {
                    Picker(selection: $selectedCalendarID) {
                        Text("System Default").tag("")
                        ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                            .tag(calendar.calendarIdentifier)
                        }
                    } label: {
                        Label("Add events to", systemImage: "calendar.badge.checkmark")
                    }
                }
            } footer: {
                Text("Events go to the selected calendar — e.g. a shared “Mowing” calendar the family can show or hide.")
            }
            .task {
                await loadCalendars(requestingAccess: false)
            }
            Section("Day & Start Time") {
                DatePicker("Day", selection: $model.scheduleStart, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Picker("Start time", selection: startTimeBinding) {
                    ForEach(TimeSlot.startSlots, id: \.self) { slot in
                        Text(TimeSlot.display(slot)).tag(slot)
                    }
                }
            }
            Section {
                Label(assignedSummary, systemImage: "person.2")
                    .font(.callout)
            }
        }
    }

    /// Bridges the scheduleStart Date to a working-hours "HH:mm" slot.
    private var startTimeBinding: Binding<String> {
        Binding(
            get: {
                let calendar = Calendar.current
                let mins = calendar.component(.hour, from: model.scheduleStart) * 60
                    + calendar.component(.minute, from: model.scheduleStart)
                let rounded = Int((Double(mins) / Double(TimeSlot.increment)).rounded(.up)) * TimeSlot.increment
                let clamped = min(max(rounded, TimeSlot.startMinutes), TimeSlot.maxStartMinutes)
                return TimeSlot.string(fromMinutes: clamped)
            },
            set: { newValue in
                if let date = TimeSlot.date(day: model.scheduleStart, hhmm: newValue) {
                    model.scheduleStart = date
                }
            }
        )
    }

    private var weekdayName: String {
        model.scheduleStart.formatted(.dateTime.weekday(.wide))
    }

    private var assignedCount: Int {
        let code = ScheduleBuilderModel.weekdayCode(for: model.scheduleStart)
        return customers.filter { $0.dayOfWeek == code }.count
    }

    private var assignedSummary: String {
        "\(weekdayName): \(assignedCount) customer\(assignedCount == 1 ? "" : "s") assigned"
    }

    // MARK: - Step 2: select jobs

    private var selectJobsStep: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(customers) { customer in
                    Button {
                        model.toggleSelection(customer)
                    } label: {
                        customerRow(customer)
                    }
                    .tint(.primary)
                }
            } header: {
                Text("\(weekdayName) — \(model.selectedCustomerIDs.count) selected")
            } footer: {
                Text("Customers assigned to \(weekdayName.uppercased()) are pre-selected. Tap to include or exclude anyone.")
            }
        }
    }

    private func customerRow(_ customer: Customer) -> some View {
        let selected = model.isSelected(customer)
        let dueAddOnNames = model.dueAddOns(for: customer, context: context).map(\.name)
        return HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name.isEmpty ? customer.jobTitle : customer.name)
                Text(customer.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dueAddOnNames.isEmpty {
                    Text(dueAddOnNames.map { "+ \($0)" }.joined(separator: "  "))
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                if customer.visitIntervalWeeks > 1 {
                    Text(biweeklyNote(customer))
                        .font(.caption2)
                        .foregroundStyle(model.visitIsDue(customer, context: context) ? .green : .orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let duration = customer.durationMinutes {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("TBD → \(ScheduleBuilderModel.defaultDurationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !customer.dayOfWeek.isEmpty {
                    Text(customer.dayOfWeek)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Loads the writable calendar list. Only prompts for calendar permission
    /// when the user explicitly taps the chooser; otherwise loads silently if
    /// access was already granted.
    private func loadCalendars(requestingAccess: Bool) async {
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            guard requestingAccess, await CalendarService.shared.requestAccess() else { return }
        }
        writableCalendars = CalendarService.shared.writableCalendars()
    }

    /// "Bi-weekly — due" or "Bi-weekly — visited 5 days ago".
    private func biweeklyNote(_ customer: Customer) -> String {
        let cadence = customer.visitIntervalWeeks == 2 ? "Bi-weekly" : "Every \(customer.visitIntervalWeeks) weeks"
        if model.visitIsDue(customer, context: context) { return "\(cadence) — due" }
        if let last = model.lastVisitDate(for: customer, context: context) {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: last),
                to: Calendar.current.startOfDay(for: model.scheduleStart)
            ).day ?? 0
            return "\(cadence) — visited \(days) day\(days == 1 ? "" : "s") ago"
        }
        return cadence
    }

    // MARK: - Step 3: review

    private var reviewStep: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            if !model.statusMessage.isEmpty {
                Section {
                    Label(model.statusMessage, systemImage: "map")
                        .font(.callout)
                }
            }
            Section {
                ForEach(Array(model.jobs.enumerated()), id: \.element.id) { index, job in
                    stopRow(job: job, number: index + 1, isFirst: index == 0)
                        .contentShape(Rectangle())
                        .onTapGesture { notesTarget = NotesTarget(id: job.id) }
                }
                .onMove { model.moveJobs(from: $0, to: $1) }
                .onDelete { model.removeJobs(at: $0) }
            } header: {
                Text(model.scheduleStart.formatted(.dateTime.weekday(.wide).month().day()))
            } footer: {
                Text("Drag to reorder (Edit), swipe to remove, tap a stop to edit its notes. Times re-chain automatically with drive time between stops.")
            }
        }
    }

    private func stopRow(job: JobEntry, number: Int, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let drive = model.legDriveMinutes[job.id] {
                Label(
                    isFirst ? "\(drive) min drive from start" : "\(drive) min drive",
                    systemImage: "car.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.customerName.isEmpty ? job.title : job.customerName)
                    Text(job.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(TimeSlot.display(job.start)) – \(TimeSlot.display(job.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if job.estimatedDuration {
                    Text("estimated")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            switch model.step {
            case .pickDay:
                primaryButton("Continue — Select Jobs") {
                    model.preselectCustomers(customers, context: context)
                    model.step = .selectJobs
                }
            case .selectJobs:
                primaryButton("Build Route (\(model.selectedCustomerIDs.count))") {
                    Task { await model.buildRoute(customers: customers, context: context) }
                }
                .disabled(model.selectedCustomerIDs.isEmpty || model.isWorking)
            case .review:
                primaryButton("Add to Calendar") {
                    Task { await model.sendToCalendar(context: context) }
                }
                .disabled(model.jobs.isEmpty || model.isWorking)
            }
        }
        .padding()
        .background(.bar)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if model.isWorking {
                    ProgressView()
                    Text(model.statusMessage.isEmpty ? title : model.statusMessage)
                        .fontWeight(.semibold)
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
    }

    private func shareICS() {
        if let err = model.validationError() {
            model.errorMessage = err
            return
        }
        model.errorMessage = nil
        if let url = TempFile.write(model.icsString(), name: "schrammscape.ics") {
            shareItem = ShareItem(url: url)
        }
    }
}

// MARK: - Stop detail sheet (services + notes)

private struct NotesEditorView: View {
    let model: ScheduleBuilderModel
    let jobID: JobEntry.ID
    @Environment(\.dismiss) private var dismiss

    private var job: JobEntry? {
        model.jobs.first(where: { $0.id == jobID })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let job, !job.addOnOptions.isEmpty {
                    Section("Services This Visit") {
                        ForEach(job.addOnOptions) { option in
                            Button {
                                model.toggleAddOn(jobID: jobID, name: option.name)
                            } label: {
                                HStack {
                                    Image(systemName: option.included ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(option.included ? Color.green : Color.secondary)
                                    Text(option.name)
                                    Spacer()
                                    Text("\(option.durationMinutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Job notes", text: notesBinding, axis: .vertical)
                        .lineLimit(5...12)
                }
            }
            .navigationTitle(job?.customerName ?? "Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { model.jobs.first(where: { $0.id == jobID })?.notes ?? "" },
            set: { newValue in
                if let idx = model.jobs.firstIndex(where: { $0.id == jobID }) {
                    model.jobs[idx].notes = newValue
                }
            }
        )
    }
}
