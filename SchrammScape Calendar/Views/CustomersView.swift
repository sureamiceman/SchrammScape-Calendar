//
//  CustomersView.swift
//  SchrammScape Calendar
//
//  The Customers tab: CRUD on the reference list, CSV import/export, reset.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CoreLocation

struct CustomersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Customer.sortOrder), SortDescriptor(\Customer.createdAt)])
    private var customers: [Customer]

    @State private var editing: Customer?
    @State private var showingImporter = false
    @State private var shareItem: ShareItem?
    @State private var statusMessage = ""
    @State private var isValidating = false

    var body: some View {
        NavigationStack {
            List {
                if customers.isEmpty {
                    ContentUnavailableView(
                        "No Customers",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add a customer or import a CSV.")
                    )
                }

                ForEach(customers) { customer in
                    Button {
                        editing = customer
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customer.name.isEmpty ? customer.jobTitle : customer.name)
                                .font(.headline)
                            if !customer.address.isEmpty {
                                HStack(spacing: 4) {
                                    switch customer.geocodeStatusValue {
                                    case .valid:
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                    case .failed:
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    case .unvalidated:
                                        EmptyView()
                                    }
                                    Text(customer.address)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                            if !customer.durationLabel.isEmpty {
                                Text("Duration: \(customer.durationLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
                .onDelete(perform: delete)

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showingImporter = true } label: {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }
                        Button { exportCSV() } label: {
                            Label("Export / Share CSV", systemImage: "square.and.arrow.up")
                        }
                        Button { validateAddresses() } label: {
                            Label("Validate Addresses", systemImage: "checkmark.seal")
                        }
                        .disabled(isValidating)
                        Divider()
                        Button(role: .destructive) { resetToDefault() } label: {
                            Label("Reset to Default List", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { addCustomer() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { customer in
                CustomerEditView(customer: customer)
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
    }

    private func addCustomer() {
        let nextOrder = (customers.map(\.sortOrder).max() ?? -1) + 1
        let customer = Customer(sortOrder: nextOrder)
        context.insert(customer)
        editing = customer
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            SyncEngine.shared.softDeleteRemote(table: "customers", id: customers[index].remoteID)
            context.delete(customers[index])
        }
    }

    private func resetToDefault() {
        for customer in customers {
            SyncEngine.shared.softDeleteRemote(table: "customers", id: customer.remoteID)
            context.delete(customer)
        }
        for (index, parsed) in DefaultCustomers.all.enumerated() {
            context.insert(parsed.makeCustomer(sortOrder: index))
        }
        statusMessage = "Restored the default customer list."
    }

    /// Runs every customer's address through Maps geocoding, storing
    /// coordinates on success and flagging addresses Maps can't find.
    private func validateAddresses() {
        isValidating = true
        statusMessage = "Validating addresses…"
        Task {
            var valid = 0
            var failures: [String] = []
            for customer in customers where !customer.address.isEmpty {
                if let location = await GeocodingService.geocode(customer.address) {
                    customer.latitude = location.coordinate.latitude
                    customer.longitude = location.coordinate.longitude
                    customer.geocodeStatusValue = .valid
                    valid += 1
                } else {
                    customer.invalidateGeocode()
                    customer.geocodeStatusValue = .failed
                    failures.append(customer.name.isEmpty ? customer.address : customer.name)
                }
                customer.markDirty()
            }
            try? context.save()
            statusMessage = failures.isEmpty
                ? "All \(valid) addresses validated."
                : "\(valid) validated. Maps could not find: \(failures.joined(separator: ", ")). Edit those addresses and validate again."
            isValidating = false
        }
    }

    private func exportCSV() {
        let csv = CSVSupport.exportCSV(customers)
        if let url = TempFile.write(csv, name: "MOW_REF.csv") {
            shareItem = ShareItem(url: url)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let parsed = CSVSupport.parseCustomers(text)
                guard !parsed.isEmpty else {
                    statusMessage = "No usable rows found in that CSV."
                    return
                }
                for customer in customers {
                    SyncEngine.shared.softDeleteRemote(table: "customers", id: customer.remoteID)
                    context.delete(customer)
                }
                for (index, item) in parsed.enumerated() {
                    context.insert(item.makeCustomer(sortOrder: index))
                }
                statusMessage = "Imported \(parsed.count) customers."
            } catch {
                statusMessage = "Could not read that file: \(error.localizedDescription)"
            }
        case .failure(let error):
            statusMessage = "Import cancelled: \(error.localizedDescription)"
        }
    }
}
