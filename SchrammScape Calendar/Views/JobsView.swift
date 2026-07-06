//
//  JobsView.swift
//  SchrammScape Calendar
//
//  The Jobs tab: the catalog of services the business offers.
//  "Mow, Edge and Blowoff" is the default; the user can add their own
//  (Mulch Spreading, Bush Trimming and Cleanup, Apply River Rock, …).
//

import SwiftUI
import SwiftData

struct JobsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\JobType.sortOrder), SortDescriptor(\JobType.createdAt)])
    private var jobTypes: [JobType]

    @State private var editing: JobType?

    var body: some View {
        NavigationStack {
            List {
                if jobTypes.isEmpty {
                    ContentUnavailableView(
                        "No Jobs",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Add the services your business offers.")
                    )
                }
                ForEach(jobTypes) { jobType in
                    Button {
                        editing = jobType
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(jobType.name)
                                        .font(.headline)
                                    if jobType.isDefault {
                                        Text("DEFAULT")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.green.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text("\(jobType.defaultDurationMinutes) min default")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addJobType() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { jobType in
                JobTypeEditView(jobType: jobType)
            }
        }
    }

    private func addJobType() {
        let nextOrder = (jobTypes.map(\.sortOrder).max() ?? -1) + 1
        let jobType = JobType(sortOrder: nextOrder)
        context.insert(jobType)
        editing = jobType
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(jobTypes[index]) }
    }
}

private struct JobTypeEditView: View {
    @Bindable var jobType: JobType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Job name (e.g. Mulch Spreading)", text: $jobType.name)
                    Stepper(
                        "Default duration: \(jobType.defaultDurationMinutes) min",
                        value: $jobType.defaultDurationMinutes,
                        in: 5...480,
                        step: 5
                    )
                }
                Section {
                    Toggle("Default service for routine visits", isOn: $jobType.isDefault)
                } footer: {
                    Text("The default service is what a normal scheduled visit includes (e.g. Mow, Edge and Blowoff).")
                }
            }
            .navigationTitle("Edit Job")
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
