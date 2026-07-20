//
//  SyncEngine.swift
//  SchrammScape Calendar
//
//  Offline-first sync between local SwiftData and the shared Supabase
//  backend. Push: rows flagged dirty are upserted by their client-generated
//  id. Pull: rows with updated_at newer than the per-table cursor are applied
//  locally (last write wins; locally-dirty rows are never overwritten because
//  push runs first). Failures leave dirty flags intact for the next trigger.
//

import Foundation
import SwiftData
import Supabase

@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private var container: ModelContainer?
    private var isSyncing = false
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func setUp(container: ModelContainer) {
        self.container = container
    }

    private var client: SupabaseClient { SupabaseService.shared.client }

    /// Push everything dirty, then pull everything new. Safe to call often.
    func syncNow() async {
        guard !isSyncing,
              SupabaseService.shared.isSignedIn,
              let context = container?.mainContext else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await pushCustomers(context)
            try await pushServiceItems(context)
            try await pushJobTypes(context)
            try await pushWorkRecords(context)
            try await pushInvoices(context)
            try await pushMileage(context)
            try context.save()

            try await pullCustomers(context)
            try await pullServiceItems(context)
            try await pullJobTypes(context)
            try await pullWorkRecords(context)
            try await pullInvoices(context)
            try await pullMileage(context)
            try context.save()
        } catch {
            // Offline or server hiccup: dirty flags persist; next trigger retries.
        }
    }

    /// Marks a remote row deleted (fire-and-forget) when it's removed locally.
    /// Other devices drop it on their next pull.
    func softDeleteRemote(table: String, id: UUID) {
        guard SupabaseService.shared.isSignedIn else { return }
        let stamp = iso.string(from: .now)
        Task {
            try? await client.from(table)
                .update(["deleted_at": stamp])
                .eq("id", value: id)
                .execute()
        }
    }

    // MARK: - Cursors

    private func cursor(_ table: String) -> String? {
        UserDefaults.standard.string(forKey: "sync.cursor.\(table)")
    }

    private func advanceCursor(_ table: String, to dates: [Date?]) {
        if let newest = dates.compactMap({ $0 }).max() {
            UserDefaults.standard.set(iso.string(from: newest), forKey: "sync.cursor.\(table)")
        }
    }

    private func fetchNew<DTO: Decodable>(_ table: String) async throws -> [DTO] {
        var query = client.from(table).select()
        if let cursor = cursor(table) {
            query = query.gt("updated_at", value: cursor)
        }
        return try await query.order("updated_at").execute().value
    }

    // MARK: - Customers

    private struct CustomerDTO: Codable {
        var id: UUID
        var name: String
        var address: String
        var jobTitle: String
        var durationLabel: String
        var sortOrder: Int
        var dayOfWeek: String
        var mower: String
        var details: String
        var phone: String
        var email: String
        var height: String
        var latitude: Double?
        var longitude: Double?
        var geocodeStatus: String
        var visitIntervalWeeks: Int
        var defaultRate: Double
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, address, mower, details, phone, email, height, latitude, longitude
            case jobTitle = "job_title"
            case durationLabel = "duration_label"
            case sortOrder = "sort_order"
            case dayOfWeek = "day_of_week"
            case geocodeStatus = "geocode_status"
            case visitIntervalWeeks = "visit_interval_weeks"
            case defaultRate = "default_rate"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: Customer) {
            id = model.remoteID
            name = model.name
            address = model.address
            jobTitle = model.jobTitle
            durationLabel = model.durationLabel
            sortOrder = model.sortOrder
            dayOfWeek = model.dayOfWeek
            mower = model.mower
            details = model.details
            phone = model.phone
            email = model.email
            height = model.height
            latitude = model.latitude
            longitude = model.longitude
            geocodeStatus = model.geocodeStatus
            visitIntervalWeeks = model.visitIntervalWeeks
            defaultRate = model.defaultRate
        }

        func apply(to model: Customer) {
            model.name = name
            model.address = address
            model.jobTitle = jobTitle
            model.durationLabel = durationLabel
            model.sortOrder = sortOrder
            model.dayOfWeek = dayOfWeek
            model.mower = mower
            model.details = details
            model.phone = phone
            model.email = email
            model.height = height
            model.latitude = latitude
            model.longitude = longitude
            model.geocodeStatus = geocodeStatus
            model.visitIntervalWeeks = visitIntervalWeeks
            model.defaultRate = defaultRate
        }
    }

    private func pushCustomers(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        try await client.from("customers").upsert(dirty.map(CustomerDTO.init)).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullCustomers(_ context: ModelContext) async throws {
        let incoming: [CustomerDTO] = try await fetchNew("customers")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<Customer>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                if let local { context.delete(local) }
                continue
            }
            if let local {
                guard !local.isDirty else { continue }
                dto.apply(to: local)
                local.syncedAt = .now
            } else {
                let model = Customer()
                model.remoteID = dto.id
                dto.apply(to: model)
                model.isDirty = false
                model.syncedAt = .now
                context.insert(model)
            }
        }
        advanceCursor("customers", to: incoming.map(\.updatedAt))
    }

    // MARK: - Service items

    private struct ServiceItemDTO: Codable {
        var id: UUID
        var customerId: UUID?
        var name: String
        var durationMinutes: Int
        var intervalVisits: Int
        var sortOrder: Int
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name
            case customerId = "customer_id"
            case durationMinutes = "duration_minutes"
            case intervalVisits = "interval_visits"
            case sortOrder = "sort_order"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: ServiceItem) {
            id = model.remoteID
            customerId = model.customer?.remoteID
            name = model.name
            durationMinutes = model.durationMinutes
            intervalVisits = model.intervalVisits
            sortOrder = model.sortOrder
        }
    }

    private func pushServiceItems(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<ServiceItem>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        try await client.from("service_items").upsert(dirty.map(ServiceItemDTO.init)).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullServiceItems(_ context: ModelContext) async throws {
        let incoming: [ServiceItemDTO] = try await fetchNew("service_items")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<ServiceItem>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                if let local { context.delete(local) }
                continue
            }
            let model: ServiceItem
            if let local {
                guard !local.isDirty else { continue }
                model = local
            } else {
                model = ServiceItem()
                model.remoteID = dto.id
                context.insert(model)
            }
            model.name = dto.name
            model.durationMinutes = dto.durationMinutes
            model.intervalVisits = dto.intervalVisits
            model.sortOrder = dto.sortOrder
            if let customerId = dto.customerId {
                model.customer = try context.fetch(
                    FetchDescriptor<Customer>(predicate: #Predicate { $0.remoteID == customerId })
                ).first
            }
            model.isDirty = false
            model.syncedAt = .now
        }
        advanceCursor("service_items", to: incoming.map(\.updatedAt))
    }

    // MARK: - Job types

    private struct JobTypeDTO: Codable {
        var id: UUID
        var name: String
        var defaultDurationMinutes: Int
        var isDefault: Bool
        var sortOrder: Int
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name
            case defaultDurationMinutes = "default_duration_minutes"
            case isDefault = "is_default"
            case sortOrder = "sort_order"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: JobType) {
            id = model.remoteID
            name = model.name
            defaultDurationMinutes = model.defaultDurationMinutes
            isDefault = model.isDefault
            sortOrder = model.sortOrder
        }
    }

    private func pushJobTypes(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<JobType>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        try await client.from("job_types").upsert(dirty.map(JobTypeDTO.init)).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullJobTypes(_ context: ModelContext) async throws {
        let incoming: [JobTypeDTO] = try await fetchNew("job_types")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<JobType>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                if let local { context.delete(local) }
                continue
            }
            let model: JobType
            if let local {
                guard !local.isDirty else { continue }
                model = local
            } else {
                model = JobType()
                model.remoteID = dto.id
                context.insert(model)
            }
            model.name = dto.name
            model.defaultDurationMinutes = dto.defaultDurationMinutes
            model.isDefault = dto.isDefault
            model.sortOrder = dto.sortOrder
            model.isDirty = false
            model.syncedAt = .now
        }
        advanceCursor("job_types", to: incoming.map(\.updatedAt))
    }

    // MARK: - Work records

    private struct WorkRecordDTO: Codable {
        var id: UUID
        var customerName: String
        var address: String
        var jobTitle: String
        var phone: String
        var notes: String
        var scheduledStart: Date
        var scheduledEnd: Date
        var actualStart: Date?
        var actualEnd: Date?
        var status: String
        var plannedDurationMinutes: Int?
        var servicesPerformed: [String]
        var extraServices: [String]
        var extraNotes: String
        var invoiceNumber: String?
        var eventIdentifier: String?
        var latitude: Double?
        var longitude: Double?
        var assignedTo: UUID?
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, address, phone, notes, status, latitude, longitude
            case customerName = "customer_name"
            case jobTitle = "job_title"
            case scheduledStart = "scheduled_start"
            case scheduledEnd = "scheduled_end"
            case actualStart = "actual_start"
            case actualEnd = "actual_end"
            case plannedDurationMinutes = "planned_duration_minutes"
            case servicesPerformed = "services_performed"
            case extraServices = "extra_services"
            case extraNotes = "extra_notes"
            case invoiceNumber = "invoice_number"
            case eventIdentifier = "event_identifier"
            case assignedTo = "assigned_to"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: WorkRecord) {
            id = model.remoteID
            customerName = model.customerName
            address = model.address
            jobTitle = model.jobTitle
            phone = model.phone
            notes = model.notes
            scheduledStart = model.scheduledStart
            scheduledEnd = model.scheduledEnd
            actualStart = model.actualStart
            actualEnd = model.actualEnd
            status = model.status
            plannedDurationMinutes = model.plannedDurationMinutes
            servicesPerformed = model.servicesPerformed
            extraServices = model.extraServices
            extraNotes = model.extraNotes
            invoiceNumber = model.invoiceNumber
            eventIdentifier = model.eventIdentifier
            latitude = model.latitude
            longitude = model.longitude
            assignedTo = model.assignedTo
        }

        func apply(to model: WorkRecord) {
            model.customerName = customerName
            model.address = address
            model.jobTitle = jobTitle
            model.phone = phone
            model.notes = notes
            model.scheduledStart = scheduledStart
            model.scheduledEnd = scheduledEnd
            model.actualStart = actualStart
            model.actualEnd = actualEnd
            model.status = status
            model.plannedDurationMinutes = plannedDurationMinutes
            model.servicesPerformed = servicesPerformed
            model.extraServices = extraServices
            model.extraNotes = extraNotes
            model.invoiceNumber = invoiceNumber
            model.eventIdentifier = eventIdentifier
            model.latitude = latitude
            model.longitude = longitude
            model.assignedTo = assignedTo
        }
    }

    private func pushWorkRecords(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<WorkRecord>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        // Default assignment: jobs belong to whoever scheduled them.
        if let me = SupabaseService.shared.currentUserID {
            for model in dirty where model.assignedTo == nil { model.assignedTo = me }
        }
        try await client.from("work_records").upsert(dirty.map(WorkRecordDTO.init)).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullWorkRecords(_ context: ModelContext) async throws {
        let incoming: [WorkRecordDTO] = try await fetchNew("work_records")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<WorkRecord>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                // Completed history survives remote deletion (billing record).
                if let local, local.statusValue != .completed { context.delete(local) }
                continue
            }
            if let local {
                guard !local.isDirty else { continue }
                dto.apply(to: local)
                local.syncedAt = .now
            } else {
                let model = WorkRecord()
                model.remoteID = dto.id
                dto.apply(to: model)
                model.isDirty = false
                model.syncedAt = .now
                context.insert(model)
            }
        }
        advanceCursor("work_records", to: incoming.map(\.updatedAt))
    }

    // MARK: - Invoices

    private struct InvoiceDTO: Codable {
        var id: UUID
        var number: String
        var customerName: String
        var customerAddress: String
        var issueDate: Date
        var status: String
        var notes: String
        var lines: [InvoiceLine]
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, number, status, notes, lines
            case customerName = "customer_name"
            case customerAddress = "customer_address"
            case issueDate = "issue_date"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: Invoice) {
            id = model.remoteID
            number = model.number
            customerName = model.customerName
            customerAddress = model.customerAddress
            issueDate = model.issueDate
            status = model.status
            notes = model.notes
            lines = model.lines
        }
    }

    private func pushInvoices(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        try await client.from("invoices").upsert(dirty.map(InvoiceDTO.init)).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullInvoices(_ context: ModelContext) async throws {
        let incoming: [InvoiceDTO] = try await fetchNew("invoices")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                if let local { context.delete(local) }
                continue
            }
            let model: Invoice
            if let local {
                guard !local.isDirty else { continue }
                model = local
            } else {
                model = Invoice()
                model.remoteID = dto.id
                context.insert(model)
            }
            model.number = dto.number
            model.customerName = dto.customerName
            model.customerAddress = dto.customerAddress
            model.issueDate = dto.issueDate
            model.status = dto.status
            model.notes = dto.notes
            model.lines = dto.lines
            model.isDirty = false
            model.syncedAt = .now
        }
        advanceCursor("invoices", to: incoming.map(\.updatedAt))
    }

    // MARK: - Mileage

    private struct MileageDTO: Codable {
        var id: UUID
        var date: Date
        var fromLabel: String
        var toLabel: String
        var miles: Double
        var eventIdentifier: String?
        var userId: UUID?
        var updatedAt: Date?
        var deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, date, miles
            case fromLabel = "from_label"
            case toLabel = "to_label"
            case eventIdentifier = "event_identifier"
            case userId = "user_id"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        init(_ model: MileageEntry, userId: UUID?) {
            id = model.remoteID
            date = model.date
            fromLabel = model.fromLabel
            toLabel = model.toLabel
            miles = model.miles
            eventIdentifier = model.eventIdentifier
            self.userId = userId
        }
    }

    private func pushMileage(_ context: ModelContext) async throws {
        let dirty = try context.fetch(FetchDescriptor<MileageEntry>(predicate: #Predicate { $0.isDirty }))
        guard !dirty.isEmpty else { return }
        let me = SupabaseService.shared.currentUserID
        try await client.from("mileage_entries").upsert(dirty.map { MileageDTO($0, userId: me) }).execute()
        for model in dirty { model.isDirty = false; model.syncedAt = .now }
    }

    private func pullMileage(_ context: ModelContext) async throws {
        let incoming: [MileageDTO] = try await fetchNew("mileage_entries")
        guard !incoming.isEmpty else { return }
        for dto in incoming {
            let id = dto.id
            let local = try context.fetch(FetchDescriptor<MileageEntry>(predicate: #Predicate { $0.remoteID == id })).first
            if dto.deletedAt != nil {
                if let local { context.delete(local) }
                continue
            }
            let model: MileageEntry
            if let local {
                guard !local.isDirty else { continue }
                model = local
            } else {
                model = MileageEntry()
                model.remoteID = dto.id
                context.insert(model)
            }
            model.date = dto.date
            model.fromLabel = dto.fromLabel
            model.toLabel = dto.toLabel
            model.miles = dto.miles
            model.eventIdentifier = dto.eventIdentifier
            model.isDirty = false
            model.syncedAt = .now
        }
        advanceCursor("mileage_entries", to: incoming.map(\.updatedAt))
    }
}
