//
//  CustomerEditView.swift
//  SchrammScape Calendar
//

import SwiftUI
import SwiftData
import CoreLocation

struct CustomerEditView: View {
    @Bindable var customer: Customer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\JobType.sortOrder)]) private var jobTypes: [JobType]
    @State private var isValidating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Customer name", text: $customer.name)
                    TextField("Address", text: $customer.address)
                        .onChange(of: customer.address) { _, _ in
                            customer.invalidateGeocode()
                        }
                    addressValidationRow
                }
                Section("Job") {
                    TextField("Job title", text: $customer.jobTitle)
                    TextField("Duration (minutes or TBD)", text: $customer.durationLabel)
                        .keyboardType(.numbersAndPunctuation)
                    HStack {
                        Text("Rate per visit")
                        Spacer()
                        TextField("$0", value: $customer.defaultRate, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                }
                Section("Schedule") {
                    Picker("Day of week", selection: $customer.dayOfWeek) {
                        Text("Unassigned").tag("")
                        ForEach(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], id: \.self) { day in
                            Text(day).tag(day)
                        }
                    }
                    Picker("Visit frequency", selection: $customer.visitIntervalWeeks) {
                        Text("Weekly").tag(1)
                        Text("Bi-Weekly").tag(2)
                        Text("Every 3 Weeks").tag(3)
                        Text("Monthly").tag(4)
                    }
                    TextField("Mower (e.g. 42, PUSH)", text: $customer.mower)
                    TextField("Cutting height (e.g. 3.5)", text: $customer.height)
                        .keyboardType(.decimalPad)
                }
                Section {
                    ForEach(customer.sortedServices) { service in
                        ServiceItemRow(service: service)
                    }
                    .onDelete(perform: deleteServices)
                    Menu {
                        ForEach(jobTypes.filter { !$0.isDefault }) { jobType in
                            Button(jobType.name) {
                                addService(name: jobType.name, duration: jobType.defaultDurationMinutes)
                            }
                        }
                        Divider()
                        Button("Custom Service…") {
                            addService(name: "", duration: 15)
                        }
                    } label: {
                        Label("Add Service", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Add-On Services")
                } footer: {
                    Text("Recurring extras on their own rotation, like weeding every 2nd visit. Manage the job catalog in the Jobs tab.")
                }
                Section("Contact") {
                    TextField("Phone", text: $customer.phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $customer.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Details") {
                    TextField("Job notes", text: $customer.details, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var addressValidationRow: some View {
        HStack {
            switch customer.geocodeStatusValue {
            case .valid:
                Label("Address validated", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("Maps couldn't find this address", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .unvalidated:
                Label("Not validated yet", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isValidating {
                ProgressView()
            } else {
                Button("Validate") { validateAddress() }
                    .disabled(customer.address.isEmpty)
            }
        }
        .font(.callout)
    }

    private func validateAddress() {
        isValidating = true
        Task {
            if let location = await GeocodingService.geocode(customer.address) {
                customer.latitude = location.coordinate.latitude
                customer.longitude = location.coordinate.longitude
                customer.geocodeStatusValue = .valid
            } else {
                customer.invalidateGeocode()
                customer.geocodeStatusValue = .failed
            }
            isValidating = false
        }
    }

    private func addService(name: String, duration: Int) {
        let nextOrder = (customer.sortedServices.map(\.sortOrder).max() ?? -1) + 1
        let service = ServiceItem(
            name: name,
            durationMinutes: duration,
            intervalVisits: 2,
            sortOrder: nextOrder,
            customer: customer
        )
        context.insert(service)
    }

    private func deleteServices(_ offsets: IndexSet) {
        let sorted = customer.sortedServices
        for index in offsets where index < sorted.count {
            context.delete(sorted[index])
        }
    }
}

/// One editable add-on service row: name, duration stepper, rotation picker.
private struct ServiceItemRow: View {
    @Bindable var service: ServiceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Service name", text: $service.name)
            HStack {
                Stepper(
                    "\(service.durationMinutes) min",
                    value: $service.durationMinutes,
                    in: 5...240,
                    step: 5
                )
                .font(.caption)
            }
            Picker("Frequency", selection: $service.intervalVisits) {
                Text("Every visit").tag(1)
                Text("Every 2nd visit").tag(2)
                Text("Every 3rd visit").tag(3)
                Text("Every 4th visit").tag(4)
            }
            .font(.caption)
        }
    }
}
