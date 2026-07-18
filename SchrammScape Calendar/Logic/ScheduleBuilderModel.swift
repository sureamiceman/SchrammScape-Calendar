//
//  ScheduleBuilderModel.swift
//  SchrammScape Calendar
//
//  State machine for the day-based schedule wizard:
//  pick a day → select the day's jobs → review the optimized route → send to calendar.
//

import SwiftUI
import SwiftData
import CoreLocation

@MainActor
@Observable
final class ScheduleBuilderModel {

    enum Step {
        case pickDay
        case selectJobs
        case review
    }

    var step: Step = .pickDay
    /// The chosen starting date & time; the first job starts here.
    var scheduleStart: Date = defaultScheduleStart()
    /// Customers included in the day being built (step 2 multi-select).
    var selectedCustomerIDs: Set<PersistentIdentifier> = []
    /// The optimized, time-chained route shown in the review step.
    var jobs: [JobEntry] = []
    /// Drive minutes to reach each job from the previous stop (or the start location).
    var legDriveMinutes: [UUID: Int] = [:]
    var statusMessage = ""
    var errorMessage: String?
    var isWorking = false

    /// Where the route was optimized from; reused when re-chaining after edits.
    private var routeStartCoordinate: CLLocationCoordinate2D?

    /// Fallback duration for customers whose duration is blank/TBD.
    static let defaultDurationMinutes = 45

    /// Today at the first selectable slot (6:00 AM), or now rounded up if later.
    private static func defaultScheduleStart() -> Date {
        let now = Date.now
        let mins = Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
        let rounded = Int((Double(mins) / Double(TimeSlot.increment)).rounded(.up)) * TimeSlot.increment
        let clamped = min(max(rounded, TimeSlot.startMinutes), TimeSlot.maxStartMinutes)
        return TimeSlot.date(day: now, hhmm: TimeSlot.string(fromMinutes: clamped)) ?? now
    }

    // MARK: - Step 1: day selection

    /// "MON"..."SUN" for a date, matching `Customer.dayOfWeek`.
    static func weekdayCode(for date: Date) -> String {
        let codes = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        return codes[Calendar.current.component(.weekday, from: date) - 1]
    }

    /// Auto-selects customers assigned to the chosen weekday whose visit is due
    /// (weekly always; bi-weekly only when enough time has passed since the last visit).
    func preselectCustomers(_ customers: [Customer], context: ModelContext) {
        let code = Self.weekdayCode(for: scheduleStart)
        selectedCustomerIDs = Set(
            customers
                .filter { $0.dayOfWeek == code && visitIsDue($0, context: context) }
                .map(\.persistentModelID)
        )
    }

    /// Weekly customers are always due; longer cadences are due once enough
    /// calendar time has passed since their most recent visit.
    func visitIsDue(_ customer: Customer, context: ModelContext) -> Bool {
        guard customer.visitIntervalWeeks > 1 else { return true }
        guard let last = lastVisitDate(for: customer, context: context) else { return true }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: scheduleStart)
        ).day ?? 0
        // 3-day grace so a Monday-to-Monday cadence never slips a week.
        return days >= customer.visitIntervalWeeks * 7 - 3
    }

    /// The customer's most recent visit before the day being scheduled.
    func lastVisitDate(for customer: Customer, context: ModelContext) -> Date? {
        let name = customer.name
        let dayStart = Calendar.current.startOfDay(for: scheduleStart)
        var descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.customerName == name && $0.scheduledStart < dayStart },
            sortBy: [SortDescriptor(\.scheduledStart, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.scheduledStart
    }

    /// Add-on services due on the next visit, based on how many completed
    /// visits have passed since each was last performed.
    func dueAddOns(for customer: Customer, context: ModelContext) -> [ServiceItem] {
        let addOns = customer.sortedServices
        guard !addOns.isEmpty else { return [] }
        let name = customer.name
        let completed = WorkRecord.Status.completed.rawValue
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.customerName == name && $0.status == completed },
            sortBy: [SortDescriptor(\.scheduledStart, order: .reverse)]
        )
        let history = (try? context.fetch(descriptor)) ?? []
        return addOns.filter { service in
            guard service.intervalVisits > 1 else { return true }
            // How many completed visits ago the service was last performed.
            guard let visitsAgo = history.firstIndex(where: { $0.servicesPerformed.contains(service.name) }) else {
                return true  // never done → due now
            }
            // Done on the most recent visit → visitsAgo 0 → next visit is 1 later.
            return visitsAgo + 1 >= service.intervalVisits
        }
    }

    func isSelected(_ customer: Customer) -> Bool {
        selectedCustomerIDs.contains(customer.persistentModelID)
    }

    func toggleSelection(_ customer: Customer) {
        if selectedCustomerIDs.contains(customer.persistentModelID) {
            selectedCustomerIDs.remove(customer.persistentModelID)
        } else {
            selectedCustomerIDs.insert(customer.persistentModelID)
        }
    }

    // MARK: - Step 2 → 3: build the optimized route

    func buildRoute(customers: [Customer], context: ModelContext) async {
        errorMessage = nil
        let selected = customers.filter { selectedCustomerIDs.contains($0.persistentModelID) }
        guard !selected.isEmpty else {
            errorMessage = "Select at least one customer."
            return
        }
        isWorking = true
        defer { isWorking = false }

        // Every stop needs coordinates; geocode stragglers on the fly.
        statusMessage = "Checking addresses…"
        for customer in selected where customer.latitude == nil && !customer.address.isEmpty {
            if let location = await GeocodingService.geocode(customer.address) {
                customer.latitude = location.coordinate.latitude
                customer.longitude = location.coordinate.longitude
                customer.geocodeStatusValue = .valid
            }
        }
        let unlocatable = selected.filter { $0.latitude == nil }.map(\.name)
        guard unlocatable.isEmpty else {
            errorMessage = "Maps can't locate: \(unlocatable.joined(separator: ", ")). Fix those addresses in the Customers tab, then try again."
            return
        }

        statusMessage = "Getting your location…"
        let start: CLLocation
        do {
            start = try await LocationService.currentLocation()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        routeStartCoordinate = start.coordinate

        // First run fetches real drive times from Apple; they're cached on
        // disk afterwards, so rebuilding or reordering is nearly instant.
        statusMessage = "Calculating drive times…"
        let stopPairs = selected.map { (id: UUID(), customer: $0) }
        let stops = stopPairs.compactMap { pair -> RouteOptimizer.Stop? in
            guard let lat = pair.customer.latitude, let lon = pair.customer.longitude else { return nil }
            return RouteOptimizer.Stop(id: pair.id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        let result = await RouteOptimizer.optimize(from: start.coordinate, stops: stops) { a, b in
            await DriveTimeService.shared.travelTime(from: a, to: b)
        }

        let customersByStopID = Dictionary(uniqueKeysWithValues: stopPairs.map { ($0.id, $0.customer) })
        jobs = result.route.compactMap { customersByStopID[$0.id] }.map { makeJobEntry(for: $0, context: context) }
        await rechainTimes()

        step = .review
        statusMessage = summaryLine()
    }

    private func makeJobEntry(for customer: Customer, context: ModelContext) -> JobEntry {
        var job = JobEntry()
        job.customerName = customer.name
        job.location = customer.address
        job.phone = customer.phone
        job.latitude = customer.latitude
        job.longitude = customer.longitude
        job.baseTitle = customer.jobTitle
        job.baseServiceLabel = customer.baseServiceLabel
        if let duration = customer.durationMinutes {
            job.baseDurationMinutes = duration
        } else {
            job.baseDurationMinutes = Self.defaultDurationMinutes
            job.estimatedDuration = true
        }

        // Add-on services: due ones are pre-included; the rest can be toggled on in review.
        let dueNames = Set(dueAddOns(for: customer, context: context).map(\.name))
        job.addOnOptions = customer.sortedServices.map {
            AddOnOption(name: $0.name, durationMinutes: $0.durationMinutes, included: dueNames.contains($0.name))
        }
        recompose(&job)

        var notes = Self.notesTemplate(for: customer)
        let included = job.addOnOptions.filter(\.included).map(\.name)
        if !included.isEmpty {
            notes = "Services: \(([job.baseServiceLabel] + included).joined(separator: " + "))\n" + notes
        }
        job.notes = notes
        return job
    }

    /// Rebuilds a job's title and duration from its base pieces and included add-ons.
    private func recompose(_ job: inout JobEntry) {
        let included = job.addOnOptions.filter(\.included)
        job.durationMinutes = job.baseDurationMinutes + included.map(\.durationMinutes).reduce(0, +)
        if included.isEmpty {
            job.title = job.baseTitle
        } else {
            let services = ([job.baseServiceLabel] + included.map(\.name)).joined(separator: " + ")
            job.title = job.customerName.isEmpty ? services : "\(services) — \(job.customerName)"
        }
    }

    /// Flips an add-on at a stop and re-chains the day's times.
    func toggleAddOn(jobID: JobEntry.ID, name: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }),
              let optIdx = jobs[idx].addOnOptions.firstIndex(where: { $0.name == name }) else { return }
        jobs[idx].addOnOptions[optIdx].included.toggle()
        recompose(&jobs[idx])
        Task {
            await rechainTimes()
            statusMessage = summaryLine()
        }
    }

    /// Pre-formed notes attached to every job; "Unknown" fills any gaps.
    static func notesTemplate(for customer: Customer) -> String {
        [
            "Phone: \(customer.phone.isEmpty ? "Unknown" : customer.phone)",
            "Mower: \(customer.mower.isEmpty ? "Unknown" : customer.mower)",
            "Height: \(customer.height.isEmpty ? "Unknown" : customer.height)",
            "Additional Info: \(customer.details)"
        ].joined(separator: "\n")
    }

    // MARK: - Step 3: review edits

    func moveJobs(from source: IndexSet, to destination: Int) {
        jobs.move(fromOffsets: source, toOffset: destination)
        Task {
            await rechainTimes()
            statusMessage = summaryLine()
        }
    }

    func removeJobs(at offsets: IndexSet, context: ModelContext) {
        let removed = offsets.compactMap { jobs.indices.contains($0) ? jobs[$0] : nil }
        jobs.remove(atOffsets: offsets)
        // A job already sent to the calendar takes its event and work record with it.
        for job in removed {
            if let eventId = job.eventIdentifier {
                try? CalendarService.shared.remove(identifier: eventId)
                deleteWorkRecord(eventIdentifier: eventId, context: context)
            }
        }
        Task {
            await rechainTimes()
            statusMessage = jobs.isEmpty ? "" : summaryLine()
        }
    }

    /// Deletes the persistent WorkRecord backing a removed calendar event.
    private func deleteWorkRecord(eventIdentifier: String, context: ModelContext) {
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate { $0.eventIdentifier == eventIdentifier }
        )
        guard let record = try? context.fetch(descriptor).first else { return }
        JobAlertService.shared.cancelAlerts(record: record)
        context.delete(record)
        try? context.save()
    }

    /// First job starts at `scheduleStart`; each following job starts at the
    /// previous job's end plus the real drive time (rounded up to 5 minutes).
    /// Drive times come from the DriveTimeService cache, so this is instant
    /// after the route was built once.
    func rechainTimes() async {
        guard !jobs.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: scheduleStart)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleStart)
        var cursor = (comps.hour ?? 8) * 60 + (comps.minute ?? 0)
        legDriveMinutes = [:]

        var previous = routeStartCoordinate
        for idx in jobs.indices {
            jobs[idx].day = day
            if let from = previous, let lat = jobs[idx].latitude, let lon = jobs[idx].longitude {
                let to = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let seconds = await DriveTimeService.shared.travelTime(from: from, to: to)
                let minutes = max(5, Int((seconds / 60 / 5).rounded(.up)) * 5)
                legDriveMinutes[jobs[idx].id] = minutes
                // The first job starts at the chosen time; its leg is info only.
                if idx > 0 { cursor += minutes }
            }
            jobs[idx].start = TimeSlot.string(fromMinutes: cursor)
            cursor += jobs[idx].durationMinutes ?? Self.defaultDurationMinutes
            jobs[idx].end = TimeSlot.string(fromMinutes: cursor)
            if let lat = jobs[idx].latitude, let lon = jobs[idx].longitude {
                previous = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
    }

    /// "6 stops — 4:35 of work, 40 min driving"
    func summaryLine() -> String {
        let work = jobs.compactMap(\.durationMinutes).reduce(0, +)
        let drive = jobs.dropFirst().compactMap { legDriveMinutes[$0.id] }.reduce(0, +)
        let workLabel = String(format: "%d:%02d", work / 60, work % 60)
        var line = "\(jobs.count) stop\(jobs.count == 1 ? "" : "s") — \(workLabel) of work"
        if drive > 0 { line += ", \(drive) min driving" }
        return line
    }

    /// Back to a fresh step 1 (e.g. after the day was sent to the calendar).
    func reset() {
        step = .pickDay
        jobs = []
        legDriveMinutes = [:]
        selectedCustomerIDs = []
        routeStartCoordinate = nil
        statusMessage = ""
        errorMessage = nil
        scheduleStart = Self.defaultScheduleStart()
    }

    // MARK: - Validation & export

    func validationError() -> String? {
        let filled = jobs.filter { !$0.isEmpty }
        if filled.isEmpty { return "Build a route first." }
        for (i, job) in filled.enumerated() {
            if job.title.isEmpty { return "Job \(i + 1) is missing a title." }
            if job.start.isEmpty || job.end.isEmpty { return "Job \(i + 1) needs a start and end time." }
            guard let s = TimeSlot.minutes(from: job.start),
                  let e = TimeSlot.minutes(from: job.end), e > s else {
                return "Job \(i + 1): end time must be after start time."
            }
        }
        return nil
    }

    func scheduledEvents() -> [ScheduledEvent] {
        jobs.filter { !$0.isEmpty }.compactMap { job in
            guard let start = TimeSlot.date(day: job.day, hhmm: job.start),
                  let end = TimeSlot.date(day: job.day, hhmm: job.end) else { return nil }
            return ScheduledEvent(title: job.title, location: job.location, notes: job.notes, start: start, end: end)
        }
    }

    func icsString() -> String {
        ICSBuilder.build(events: scheduledEvents())
    }

    // MARK: - Calendar

    func sendToCalendar(context: ModelContext) async {
        errorMessage = nil
        if let err = validationError() { errorMessage = err; return }
        isWorking = true
        defer { isWorking = false }

        guard await CalendarService.shared.requestAccess() else {
            errorMessage = "Calendar access was denied. Enable it in Settings › Privacy › Calendars."
            return
        }

        var created = 0
        var updated = 0
        do {
            for idx in jobs.indices where !jobs[idx].isEmpty {
                let job = jobs[idx]
                guard let start = TimeSlot.date(day: job.day, hhmm: job.start),
                      let end = TimeSlot.date(day: job.day, hhmm: job.end) else { continue }
                let event = ScheduledEvent(title: job.title, location: job.location, notes: job.notes, start: start, end: end)
                let hadId = jobs[idx].eventIdentifier != nil
                let newId = try CalendarService.shared.save(event, existingIdentifier: jobs[idx].eventIdentifier)
                jobs[idx].eventIdentifier = newId
                upsertWorkRecord(for: jobs[idx], start: start, end: end, context: context)
                if hadId { updated += 1 } else { created += 1 }
            }
            try? context.save()
            // If today was (re)scheduled, refresh the GPS arrival fences.
            JobAlertService.shared.syncTodayAlerts(context: context)
            var parts: [String] = []
            if created > 0 { parts.append("\(created) added") }
            if updated > 0 { parts.append("\(updated) updated") }
            statusMessage = "Calendar synced: " + parts.joined(separator: ", ") + "."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates or refreshes the persistent WorkRecord backing a sent job.
    private func upsertWorkRecord(for job: JobEntry, start: Date, end: Date, context: ModelContext) {
        let record: WorkRecord
        if let eventId = job.eventIdentifier,
           let existing = try? context.fetch(
               FetchDescriptor<WorkRecord>(predicate: #Predicate { $0.eventIdentifier == eventId })
           ).first {
            record = existing
        } else {
            record = WorkRecord()
            context.insert(record)
        }
        // A reschedule to a new address invalidates any cached geocode.
        if record.address != job.location {
            record.latitude = nil
            record.longitude = nil
        }
        // Prefer the customer's validated coordinates over runtime geocoding.
        if let lat = job.latitude, let lon = job.longitude {
            record.latitude = lat
            record.longitude = lon
        }
        record.customerName = job.customerName.isEmpty ? job.title : job.customerName
        record.address = job.location
        record.jobTitle = job.title
        record.phone = job.phone
        record.notes = job.notes
        record.scheduledStart = start
        record.scheduledEnd = end
        record.plannedDurationMinutes = job.durationMinutes
        record.servicesPerformed = job.addOnOptions.filter(\.included).map(\.name)
        record.eventIdentifier = job.eventIdentifier
    }

    func removeFromCalendar(context: ModelContext) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        guard await CalendarService.shared.requestAccess() else {
            errorMessage = "Calendar access was denied."
            return
        }

        var removed = 0
        do {
            for idx in jobs.indices {
                if let id = jobs[idx].eventIdentifier {
                    try CalendarService.shared.remove(identifier: id)
                    deleteWorkRecord(eventIdentifier: id, context: context)
                    jobs[idx].eventIdentifier = nil
                    removed += 1
                }
            }
            statusMessage = removed > 0
                ? "Removed \(removed) event\(removed == 1 ? "" : "s") from your calendar."
                : "No calendar events to remove yet."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
