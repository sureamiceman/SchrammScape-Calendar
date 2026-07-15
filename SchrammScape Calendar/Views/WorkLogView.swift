//
//  WorkLogView.swift
//  SchrammScape Calendar
//
//  History of completed work plus the summary generator: pick a customer
//  and a date range, preview the plain-text summary, then text/email/share it.
//

import SwiftUI
import SwiftData

struct WorkLogView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<WorkRecord> { $0.status == "completed" },
        sort: [SortDescriptor(\WorkRecord.scheduledStart, order: .reverse)]
    )
    private var completed: [WorkRecord]

    @State private var summaryCustomer = ""
    @State private var rangePreset: RangePreset = .thisMonth
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var shareItem: ShareItem?

    private enum RangePreset: String, CaseIterable {
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case custom = "Custom"
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                historySection
            }
            .navigationTitle("Work Log")
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    // MARK: - Summary generator

    private var customerNames: [String] {
        var seen = Set<String>()
        return completed.compactMap { record in
            guard !record.customerName.isEmpty, seen.insert(record.customerName).inserted else { return nil }
            return record.customerName
        }.sorted()
    }

    private var dateRange: (from: Date, to: Date) {
        let calendar = Calendar.current
        let now = Date.now
        switch rangePreset {
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .custom:
            return (calendar.startOfDay(for: customFrom), customTo)
        }
    }

    private var summaryRecords: [WorkRecord] {
        let (from, to) = dateRange
        let endOfTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        return completed.filter {
            $0.customerName == summaryCustomer
                && $0.scheduledStart >= from
                && $0.scheduledStart < endOfTo
        }
    }

    private var summaryText: String {
        let (from, to) = dateRange
        return WorkSummaryBuilder.period(records: summaryRecords, customerName: summaryCustomer, from: from, to: to)
    }

    private var summarySection: some View {
        Section("Work Summary") {
            if customerNames.isEmpty {
                Text("Complete a job in My Day and it will show up here.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Customer", selection: $summaryCustomer) {
                    Text("Select a customer").tag("")
                    ForEach(customerNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("Period", selection: $rangePreset) {
                    ForEach(RangePreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                if rangePreset == .custom {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $customTo, displayedComponents: .date)
                }

                if !summaryCustomer.isEmpty {
                    if summaryRecords.isEmpty {
                        Text("No completed visits for \(summaryCustomer) in this period.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(summaryText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        sendButtons
                    }
                }
            }
        }
    }

    private var sendButtons: some View {
        HStack {
            Button {
                sendMessage()
            } label: {
                Label("Message", systemImage: "message")
            }
            .buttonStyle(.bordered)
            Button {
                sendEmail()
            } label: {
                Label("Email", systemImage: "envelope")
            }
            .buttonStyle(.bordered)
            Button {
                shareSummary()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - History

    private var historySection: some View {
        let groups = Dictionary(grouping: completed) { Calendar.current.startOfDay(for: $0.scheduledStart) }
        let days = groups.keys.sorted(by: >)

        return Group {
            if completed.isEmpty {
                Section("History") {
                    Text("No completed work yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(days, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                        ForEach(groups[day] ?? [], id: \.persistentModelID) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.jobTitle)
                                HStack {
                                    if let start = record.actualStart, let end = record.actualEnd {
                                        Text("\(TimeSlot.display(start)) – \(TimeSlot.display(end))")
                                    }
                                    if let minutes = record.actualDurationMinutes {
                                        Text("(\(WorkSummaryBuilder.durationLabel(minutes)))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !record.extraServices.isEmpty {
                                    Text(record.extraServices.map { "+ \($0)" }.joined(separator: "  "))
                                        .font(.caption.bold())
                                        .foregroundStyle(.blue)
                                }
                                if !record.extraNotes.isEmpty {
                                    Text("Note: \(record.extraNotes)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let dayRecords = groups[day] ?? []
                            for index in offsets where index < dayRecords.count {
                                context.delete(dayRecords[index])
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sending

    /// The customer's phone, taken from their most recent record.
    private var summaryPhone: String {
        summaryRecords.first?.phone ?? ""
    }

    /// The customer's email, looked up live from the Customers list.
    private var summaryEmail: String {
        let name = summaryCustomer
        let descriptor = FetchDescriptor<Customer>(predicate: #Predicate { $0.name == name })
        return (try? context.fetch(descriptor).first?.email) ?? ""
    }

    private func sendMessage() {
        let digits = summaryPhone.filter { $0.isNumber || $0 == "+" }
        guard let body = summaryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "sms:\(digits)?body=\(body)") else { return }
        UIApplication.shared.open(url)
    }

    private func sendEmail() {
        let subject = "Work Summary — \(summaryCustomer)"
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let body = summaryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(summaryEmail)?subject=\(encodedSubject)&body=\(body)") else { return }
        UIApplication.shared.open(url)
    }

    private func shareSummary() {
        if let url = TempFile.write(summaryText, name: "work-summary.txt") {
            shareItem = ShareItem(url: url)
        }
    }
}
