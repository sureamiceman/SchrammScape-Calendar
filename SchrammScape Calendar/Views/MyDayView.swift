//
//  MyDayView.swift
//  SchrammScape Calendar
//
//  The "Start My Day" flow: today's route on a map, check-in / complete
//  time tracking per job, and duration feedback when a job finishes.
//

import SwiftUI
import SwiftData
import MapKit

struct MyDayView: View {
    @Environment(\.modelContext) private var context
    @State private var model = MyDayModel()
    @State private var extraJobRecord: WorkRecord?
    @State private var commentRecord: WorkRecord?
    @State private var showingPush = false
    @State private var showingPull = false

    var body: some View {
        NavigationStack {
            Group {
                if model.dayStarted {
                    dayList
                } else {
                    startScreen
                }
            }
            .navigationTitle("My Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPush = true
                        } label: {
                            Label("Push Jobs to a Later Day…", systemImage: "arrow.uturn.right.circle")
                        }
                        Button {
                            showingPull = true
                        } label: {
                            Label("Pull Jobs Forward to Today…", systemImage: "arrow.uturn.left.circle")
                        }
                    } label: {
                        Label("Replan", systemImage: "cloud.rain")
                    }
                }
            }
            .sheet(isPresented: $showingPush) {
                PushJobsView(model: model)
            }
            .sheet(isPresented: $showingPull) {
                PullJobsView(model: model)
            }
            .sheet(item: $model.feedback) { feedback in
                DurationFeedbackView(feedback: feedback, model: model)
            }
            .sheet(item: $extraJobRecord) { record in
                AddExtraJobView(record: record)
            }
            .sheet(item: $commentRecord) { record in
                ExtraCommentView(record: record)
            }
        }
    }

    // MARK: - Start screen

    private var startScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.title3)
                .foregroundStyle(.secondary)
            Button {
                model.startDay(context: context)
            } label: {
                Text("Start My Day")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Day list

    private var dayList: some View {
        List {
            if model.records.isEmpty {
                Section {
                    Text("Nothing scheduled for today. Build a day in the Schedule tab and tap “Add to Calendar”.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    routeMap
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    if !model.dayPlanSummary.isEmpty {
                        Label(model.dayPlanSummary, systemImage: "clock.fill")
                            .font(.callout)
                    }
                    if !model.progressSummary.isEmpty {
                        Label(model.progressSummary, systemImage: "chart.bar.fill")
                            .font(.callout)
                    }
                }
                if !model.statusMessage.isEmpty {
                    Section {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(model.records.enumerated()), id: \.element.persistentModelID) { index, record in
                    JobStopCard(
                        record: record,
                        stopNumber: index + 1,
                        model: model,
                        addJob: { extraJobRecord = record },
                        addComment: { commentRecord = record }
                    )
                }
            }
        }
        .refreshable {
            model.loadToday(context: context)
        }
    }

    private var routeMap: some View {
        Map(initialPosition: .automatic) {
            ForEach(Array(model.records.enumerated()), id: \.element.persistentModelID) { index, record in
                if let lat = record.latitude, let lon = record.longitude {
                    Annotation(record.customerName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                        ZStack {
                            Circle()
                                .fill(record.statusValue == .completed ? Color.green : Color.blue)
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Job stop card

private struct JobStopCard: View {
    let record: WorkRecord
    let stopNumber: Int
    let model: MyDayModel
    let addJob: () -> Void
    let addComment: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.jobTitle)
                    .font(.headline)
                Text(record.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(TimeSlot.display(record.scheduledStart)) – \(TimeSlot.display(record.scheduledEnd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !record.phone.isEmpty {
                let digits = record.phone.filter { $0.isNumber || $0 == "+" }
                HStack {
                    Label(record.phone, systemImage: "phone")
                    Spacer()
                    if let callURL = URL(string: "tel:\(digits)") {
                        Link(destination: callURL) {
                            Image(systemName: "phone.circle.fill").font(.title3)
                        }
                    }
                    if let smsURL = URL(string: "sms:\(digits)") {
                        Link(destination: smsURL) {
                            Image(systemName: "message.circle.fill").font(.title3)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !record.extraServices.isEmpty {
                Text(record.extraServices.map { "+ \($0)" }.joined(separator: "  "))
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            if !record.extraNotes.isEmpty {
                Label(record.extraNotes, systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                openDirections()
            } label: {
                Label("Directions", systemImage: "car.fill")
            }

            if record.statusValue == .scheduled || record.statusValue == .inProgress {
                Button {
                    addJob()
                } label: {
                    Label("Add Job to This Visit", systemImage: "plus.square.on.square")
                }
                Button {
                    addComment()
                } label: {
                    Label("Add Extra-Work Comment", systemImage: "text.bubble")
                }
            }

            switch record.statusValue {
            case .scheduled:
                Button {
                    model.checkIn(record, context: context)
                } label: {
                    Label("Check In", systemImage: "location.circle")
                }
                .fontWeight(.semibold)
            case .inProgress:
                if let start = record.actualStart {
                    Text("Checked in at \(TimeSlot.display(start))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    model.complete(record, context: context)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                }
                .fontWeight(.semibold)
                .foregroundStyle(.green)
            case .completed:
                if let minutes = record.actualDurationMinutes {
                    Label("Completed — \(WorkSummaryBuilder.durationLabel(minutes))", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            case .skipped:
                Label("Skipped", systemImage: "forward.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Stop \(stopNumber)")
        }
    }

    private func openDirections() {
        if let lat = record.latitude, let lon = record.longitude {
            let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
            item.name = record.customerName
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else if let encoded = record.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "maps://?daddr=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Weather replan: push jobs out

private struct PushJobsView: View {
    let model: MyDayModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [WorkRecord] = []
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var targetChoice = 1  // days ahead; 0 = custom date
    @State private var customDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var isWorking = false

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private var targetDay: Date {
        targetChoice == 0
            ? customDate
            : Calendar.current.date(byAdding: .day, value: targetChoice, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Move to") {
                    Picker("Target day", selection: $targetChoice) {
                        Text("Tomorrow").tag(1)
                        Text("+2 Days").tag(2)
                        Text("Pick Date").tag(0)
                    }
                    .pickerStyle(.segmented)
                    if targetChoice == 0 {
                        DatePicker("Day", selection: $customDate, in: tomorrow..., displayedComponents: .date)
                    }
                }
                Section("Today's remaining jobs") {
                    if candidates.isEmpty {
                        Text("No remaining jobs to push today.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates, id: \.persistentModelID) { record in
                        RecordToggleRow(
                            record: record,
                            selected: selectedIDs.contains(record.persistentModelID)
                        ) {
                            toggle(record)
                        }
                    }
                }
            }
            .navigationTitle("Push Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await push() }
                } label: {
                    HStack {
                        if isWorking { ProgressView() }
                        Text(isWorking ? "Re-optimizing routes…" : "Push \(selectedIDs.count) Job\(selectedIDs.count == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty || isWorking)
                .padding()
                .background(.bar)
            }
            .task { load() }
        }
    }

    private func load() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        let scheduled = WorkRecord.Status.scheduled.rawValue
        let inProgress = WorkRecord.Status.inProgress.rawValue
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate {
                $0.scheduledStart >= dayStart && $0.scheduledStart < dayEnd
                    && ($0.status == scheduled || $0.status == inProgress)
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        candidates = (try? context.fetch(descriptor)) ?? []
        selectedIDs = Set(candidates.map(\.persistentModelID))
    }

    private func toggle(_ record: WorkRecord) {
        if selectedIDs.contains(record.persistentModelID) {
            selectedIDs.remove(record.persistentModelID)
        } else {
            selectedIDs.insert(record.persistentModelID)
        }
    }

    private func push() async {
        isWorking = true
        let moving = candidates.filter { selectedIDs.contains($0.persistentModelID) }
        let message = await ReplanService.moveRecords(moving, toDay: targetDay, context: context)
        model.statusMessage = message
        model.loadToday(context: context)
        isWorking = false
        dismiss()
    }
}

// MARK: - Weather replan: pull jobs forward

private struct PullJobsView: View {
    let model: MyDayModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var upcoming: [WorkRecord] = []
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                if upcoming.isEmpty {
                    Section {
                        Text("Nothing scheduled in the next two weeks.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let groups = Dictionary(grouping: upcoming) { Calendar.current.startOfDay(for: $0.scheduledStart) }
                    ForEach(groups.keys.sorted(), id: \.self) { day in
                        Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                            ForEach(groups[day] ?? [], id: \.persistentModelID) { record in
                                RecordToggleRow(
                                    record: record,
                                    selected: selectedIDs.contains(record.persistentModelID)
                                ) {
                                    toggle(record)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pull Jobs to Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await pull() }
                } label: {
                    HStack {
                        if isWorking { ProgressView() }
                        Text(isWorking ? "Re-optimizing route…" : "Pull \(selectedIDs.count) Job\(selectedIDs.count == 1 ? "" : "s") to Today")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty || isWorking)
                .padding()
                .background(.bar)
            }
            .task { load() }
        }
    }

    private func load() {
        let calendar = Calendar.current
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)),
              let windowEnd = calendar.date(byAdding: .day, value: 14, to: tomorrowStart) else { return }
        let scheduled = WorkRecord.Status.scheduled.rawValue
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate {
                $0.scheduledStart >= tomorrowStart && $0.scheduledStart < windowEnd && $0.status == scheduled
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        upcoming = (try? context.fetch(descriptor)) ?? []
    }

    private func toggle(_ record: WorkRecord) {
        if selectedIDs.contains(record.persistentModelID) {
            selectedIDs.remove(record.persistentModelID)
        } else {
            selectedIDs.insert(record.persistentModelID)
        }
    }

    private func pull() async {
        isWorking = true
        let moving = upcoming.filter { selectedIDs.contains($0.persistentModelID) }
        let message = await ReplanService.moveRecords(moving, toDay: .now, context: context)
        model.statusMessage = message
        model.loadToday(context: context)
        isWorking = false
        dismiss()
    }
}

/// Checkmark row for selecting jobs in the replan sheets.
private struct RecordToggleRow: View {
    let record: WorkRecord
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.jobTitle)
                    Text("\(TimeSlot.display(record.scheduledStart)) · \(record.address)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }
}

// MARK: - On-the-spot extras

/// Adds a job from the catalog (or a custom one) to the current visit,
/// so billing records the extra line.
private struct AddExtraJobView: View {
    let record: WorkRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\JobType.sortOrder)]) private var jobTypes: [JobType]
    @State private var customName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add a job to this visit") {
                    ForEach(jobTypes.filter { !$0.isDefault }) { jobType in
                        Button {
                            add(jobType.name)
                        } label: {
                            Label(jobType.name, systemImage: "plus.circle")
                        }
                    }
                }
                Section("Custom") {
                    TextField("Describe the job", text: $customName)
                    Button("Add Custom Job") { add(customName) }
                        .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !record.extraServices.isEmpty {
                    Section("Added to this visit") {
                        ForEach(record.extraServices, id: \.self) { name in
                            Text(name)
                        }
                        .onDelete { offsets in
                            record.extraServices.remove(atOffsets: offsets)
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle(record.customerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !record.extraServices.contains(trimmed) else { return }
        record.extraServices.append(trimmed)
        try? context.save()
        customName = ""
    }
}

/// Free-form note about extra work beyond the job title (shows on the invoice).
private struct ExtraCommentView: View {
    @Bindable var record: WorkRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "e.g. Raked and cleaned up heavy clippings",
                        text: $record.extraNotes,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } footer: {
                    Text("This comment appears on the work summary/invoice for this visit.")
                }
            }
            .navigationTitle("Extra Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Duration feedback sheet

private struct DurationFeedbackView: View {
    let feedback: DurationFeedback
    let model: MyDayModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section("Time Tracking") {
                    LabeledContent("Actual", value: WorkSummaryBuilder.durationLabel(feedback.actualMinutes))
                    if let planned = feedback.plannedMinutes {
                        LabeledContent("Planned", value: WorkSummaryBuilder.durationLabel(planned))
                        if let diff = feedback.differenceMinutes {
                            LabeledContent("Difference") {
                                Text(diff == 0 ? "On time" : (diff > 0 ? "+\(diff) min" : "\(diff) min"))
                                    .foregroundStyle(diff > 0 ? .red : .green)
                            }
                        }
                    } else {
                        Text("No planned duration was set for this job.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if feedback.plannedMinutes != feedback.actualMinutes {
                        Button {
                            model.updateCustomerDuration(feedback.record, minutes: feedback.actualMinutes, context: context)
                        } label: {
                            Label("Update default duration to \(feedback.actualMinutes) min", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    Button {
                        sendSummary()
                    } label: {
                        Label("Send Summary to Customer", systemImage: "paperplane")
                    }
                }

                if !model.statusMessage.isEmpty {
                    Section {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(feedback.record.jobTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    private func sendSummary() {
        let text = WorkSummaryBuilder.singleVisit(feedback.record)
        let digits = feedback.record.phone.filter { $0.isNumber || $0 == "+" }
        if !digits.isEmpty,
           let body = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "sms:\(digits)?body=\(body)") {
            UIApplication.shared.open(url)
        } else if let url = TempFile.write(text, name: "work-summary.txt") {
            shareItem = ShareItem(url: url)
        }
    }
}
