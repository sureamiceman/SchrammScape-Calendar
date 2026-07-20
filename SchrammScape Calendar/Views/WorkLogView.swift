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
    @Query(sort: [SortDescriptor(\Invoice.createdAt, order: .reverse)])
    private var invoices: [Invoice]
    @Query(sort: [SortDescriptor(\MileageEntry.date, order: .reverse)])
    private var mileage: [MileageEntry]
    @State private var mileageRange: MileageRange = .thisMonth

    private enum MileageRange: String, CaseIterable {
        case thisMonth = "This Month"
        case thisYear = "This Year"
        case all = "All"
    }

    @State private var summaryCustomer = ""
    @State private var rangePreset: RangePreset = .thisMonth
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customTo = Date.now
    @State private var shareItem: ShareItem?
    @State private var showingInvoiceBuilder = false
    @State private var showingInvoiceSettings = false

    private enum RangePreset: String, CaseIterable {
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case custom = "Custom"
    }

    var body: some View {
        NavigationStack {
            List {
                invoicesSection
                mileageSection
                summarySection
                historySection
            }
            .navigationTitle("Billing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInvoiceSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .sheet(isPresented: $showingInvoiceBuilder) {
                InvoiceBuilderView()
            }
            .sheet(isPresented: $showingInvoiceSettings) {
                InvoiceSettingsView()
            }
        }
    }

    // MARK: - Invoices

    private var invoicesSection: some View {
        Section {
            Button {
                showingInvoiceBuilder = true
            } label: {
                Label("Create Invoice…", systemImage: "doc.badge.plus")
            }
            .disabled(completed.isEmpty)
            ForEach(invoices, id: \.persistentModelID) { invoice in
                Button {
                    shareInvoicePDF(invoice)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(invoice.number) — \(invoice.customerName)")
                            Text(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(invoice.total.formatted(.currency(code: "USD")))
                            .font(.subheadline)
                        Text(invoice.statusValue == .paid ? "PAID" : "OPEN")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (invoice.statusValue == .paid ? Color.green : Color.orange).opacity(0.2),
                                in: Capsule()
                            )
                            .foregroundStyle(invoice.statusValue == .paid ? .green : .orange)
                    }
                }
                .tint(.primary)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteInvoice(invoice)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        invoice.statusValue = invoice.statusValue == .paid ? .open : .paid
                        invoice.markDirty()
                        try? context.save()
                        Task { await SyncEngine.shared.syncNow() }
                    } label: {
                        Label(
                            invoice.statusValue == .paid ? "Reopen" : "Mark Paid",
                            systemImage: invoice.statusValue == .paid ? "arrow.uturn.left" : "checkmark.seal"
                        )
                    }
                    .tint(.green)
                }
            }
        } header: {
            Text("Invoices")
        } footer: {
            if !invoices.isEmpty {
                Text("Tap an invoice to share its PDF again. Swipe for Mark Paid / Delete.")
            }
        }
    }

    private func shareInvoicePDF(_ invoice: Invoice) {
        if let url = InvoicePDFBuilder.makePDF(invoice: invoice) {
            shareItem = ShareItem(url: url)
        }
    }

    private func deleteInvoice(_ invoice: Invoice) {
        // Un-mark its visits so they can be billed again.
        let number = invoice.number
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.invoiceNumber == number }
        )
        for record in (try? context.fetch(descriptor)) ?? [] {
            record.invoiceNumber = nil
            record.markDirty()
        }
        SyncEngine.shared.softDeleteRemote(table: "invoices", id: invoice.remoteID)
        context.delete(invoice)
        try? context.save()
        Task { await SyncEngine.shared.syncNow() }
    }

    // MARK: - Mileage (tax log)

    private var mileageInRange: [MileageEntry] {
        let calendar = Calendar.current
        switch mileageRange {
        case .thisMonth:
            return mileage.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
        case .thisYear:
            return mileage.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .year) }
        case .all:
            return mileage
        }
    }

    private var mileageSection: some View {
        Section {
            if mileage.isEmpty {
                Text("Business miles log automatically as jobs are completed.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Period", selection: $mileageRange) {
                    ForEach(MileageRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                let entries = mileageInRange
                LabeledContent("Total business miles") {
                    Text(String(format: "%.1f mi", entries.map(\.miles).reduce(0, +)))
                        .font(.headline)
                }

                let byDay = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
                ForEach(byDay.keys.sorted(by: >).prefix(5), id: \.self) { day in
                    let dayMiles = (byDay[day] ?? []).map(\.miles).reduce(0, +)
                    LabeledContent(day.formatted(.dateTime.weekday(.abbreviated).month().day())) {
                        Text(String(format: "%.1f mi", dayMiles))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    exportMileageCSV()
                } label: {
                    Label("Export Mileage CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
            }
        } header: {
            Text("Mileage")
        } footer: {
            if !mileage.isEmpty {
                Text("Road distances between completed stops, logged automatically. Recent days shown; the CSV export has every leg for your taxes.")
            }
        }
    }

    private func exportMileageCSV() {
        let entries = mileageInRange.sorted { $0.date < $1.date }
        var lines = ["Date,From,To,Miles"]
        for entry in entries {
            let date = entry.date.formatted(.iso8601.year().month().day())
            let from = entry.fromLabel.replacingOccurrences(of: ",", with: " ")
            let to = entry.toLabel.replacingOccurrences(of: ",", with: " ")
            lines.append("\(date),\(from),\(to),\(String(format: "%.2f", entry.miles))")
        }
        lines.append("TOTAL,,,\(String(format: "%.2f", entries.map(\.miles).reduce(0, +)))")
        if let url = TempFile.write(lines.joined(separator: "\n"), name: "mileage-log.csv") {
            shareItem = ShareItem(url: url)
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
                                HStack {
                                    Text(record.jobTitle)
                                    if let number = record.invoiceNumber {
                                        Text(number)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
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
                                SyncEngine.shared.softDeleteRemote(table: "work_records", id: dayRecords[index].remoteID)
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

// MARK: - Invoice letterhead settings

private struct InvoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BusinessInfo.nameKey) private var businessName = ""
    @AppStorage(BusinessInfo.addressKey) private var businessAddress = ""
    @AppStorage(BusinessInfo.phoneKey) private var businessPhone = ""
    @AppStorage(BusinessInfo.emailKey) private var businessEmail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Business name", text: $businessName, prompt: Text("SchrammScape"))
                    TextField("Address", text: $businessAddress)
                    TextField("Phone", text: $businessPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $businessEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Invoice Letterhead")
                } footer: {
                    Text("Printed in the header of every invoice PDF.")
                }
            }
            .navigationTitle("Invoice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
