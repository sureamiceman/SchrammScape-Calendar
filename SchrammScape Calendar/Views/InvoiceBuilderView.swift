//
//  InvoiceBuilderView.swift
//  SchrammScape Calendar
//
//  Builds an invoice: pick a customer, select completed visits (amounts
//  pre-filled from the customer's rate, all editable), add manual lines and
//  notes, then create the open invoice and share its PDF.
//

import SwiftUI
import SwiftData

struct InvoiceBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<WorkRecord> { $0.status == "completed" },
        sort: [SortDescriptor(\WorkRecord.scheduledStart, order: .reverse)]
    )
    private var completed: [WorkRecord]
    @Query private var customers: [Customer]

    @State private var customerName = ""
    @State private var visitLines: [VisitLine] = []
    @State private var manualLines: [ManualLine] = []
    @State private var notes = ""
    @State private var shareItem: ShareItem?
    @State private var didCreate = false

    private struct VisitLine: Identifiable {
        let id = UUID()
        let record: WorkRecord
        var included: Bool
        var amount: Double
        var details: String
    }

    private struct ManualLine: Identifiable {
        let id = UUID()
        var details = ""
        var amount: Double = 0
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                if !customerName.isEmpty {
                    visitsSection
                    manualSection
                    Section("Additional Details") {
                        TextField("Notes shown on the invoice", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    Section {
                        LabeledContent("Total") {
                            Text(total.formatted(.currency(code: "USD")))
                                .font(.headline)
                        }
                    }
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    createInvoice()
                } label: {
                    Text("Create Invoice & Share PDF")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0 || didCreate)
                .padding()
                .background(.bar)
            }
            .sheet(item: $shareItem, onDismiss: { dismiss() }) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    // MARK: - Sections

    private var customerNames: [String] {
        var seen = Set<String>()
        return completed.compactMap { record in
            guard !record.customerName.isEmpty, seen.insert(record.customerName).inserted else { return nil }
            return record.customerName
        }.sorted()
    }

    private var customerSection: some View {
        Section("Customer") {
            Picker("Customer", selection: $customerName) {
                Text("Select a customer").tag("")
                ForEach(customerNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .onChange(of: customerName) { _, _ in loadVisits() }
        }
    }

    private var visitsSection: some View {
        Section {
            if visitLines.isEmpty {
                Text("No completed visits for \(customerName).")
                    .foregroundStyle(.secondary)
            }
            ForEach($visitLines) { $line in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        line.included.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: line.included ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(line.included ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.record.scheduledStart.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                    .font(.subheadline)
                                Text(line.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if line.record.invoiceNumber != nil {
                                    Text("Already invoiced (\(line.record.invoiceNumber ?? ""))")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .tint(.primary)
                    if line.included {
                        HStack {
                            Text("Amount")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("$0", value: $line.amount, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                        }
                    }
                }
            }
        } header: {
            Text("Completed Visits")
        } footer: {
            Text("Amounts pre-fill from the customer's rate per visit and can be adjusted.")
        }
    }

    private var manualSection: some View {
        Section("Extra Lines") {
            ForEach($manualLines) { $line in
                HStack {
                    TextField("Description", text: $line.details)
                    TextField("$0", value: $line.amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }
            .onDelete { manualLines.remove(atOffsets: $0) }
            Button {
                manualLines.append(ManualLine())
            } label: {
                Label("Add Line", systemImage: "plus.circle")
            }
        }
    }

    // MARK: - Logic

    private var selectedCount: Int {
        visitLines.filter(\.included).count
            + manualLines.filter { !$0.details.isEmpty }.count
    }

    private var total: Double {
        visitLines.filter(\.included).map(\.amount).reduce(0, +)
            + manualLines.filter { !$0.details.isEmpty }.map(\.amount).reduce(0, +)
    }

    private func loadVisits() {
        let rate = customers.first(where: { $0.name == customerName })?.defaultRate ?? 0
        visitLines = completed
            .filter { $0.customerName == customerName }
            .map { record in
                var details = record.jobTitle
                let extras = record.extraServices
                if !extras.isEmpty { details += " + " + extras.joined(separator: " + ") }
                if !record.extraNotes.isEmpty { details += " (\(record.extraNotes))" }
                return VisitLine(
                    record: record,
                    included: record.invoiceNumber == nil,
                    amount: rate,
                    details: details
                )
            }
    }

    private func createInvoice() {
        let includedVisits = visitLines.filter(\.included)
        let extras = manualLines.filter { !$0.details.isEmpty }
        guard !includedVisits.isEmpty || !extras.isEmpty else { return }

        let address = customers.first(where: { $0.name == customerName })?.address
            ?? includedVisits.first?.record.address
            ?? ""
        let invoice = Invoice(
            number: Invoice.nextNumber(context: context),
            customerName: customerName,
            customerAddress: address,
            notes: notes,
            lines: includedVisits.map {
                InvoiceLine(date: $0.record.scheduledStart, details: $0.details, amount: $0.amount)
            } + extras.map {
                InvoiceLine(date: nil, details: $0.details, amount: $0.amount)
            }
        )
        context.insert(invoice)
        for line in includedVisits {
            line.record.invoiceNumber = invoice.number
        }
        try? context.save()
        didCreate = true

        if let url = InvoicePDFBuilder.makePDF(invoice: invoice) {
            shareItem = ShareItem(url: url)
        } else {
            dismiss()
        }
    }
}
