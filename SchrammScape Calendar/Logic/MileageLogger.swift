//
//  MileageLogger.swift
//  SchrammScape Calendar
//
//  Logs business driving legs as jobs complete: the road distance from the
//  previous stop of the day to the job just finished. Feeds the tax mileage
//  summaries in Billing. The first job of a day has no previous stop, so
//  legs between jobs are what get counted.
//

import Foundation
import SwiftData
import CoreLocation

@MainActor
enum MileageLogger {

    /// Records the leg that reached this just-completed job, if the previous
    /// stop is known and this job hasn't been logged already.
    static func logLeg(to record: WorkRecord, context: ModelContext) async {
        guard let eventID = record.eventIdentifier,
              let toLat = record.latitude, let toLon = record.longitude else { return }

        // One entry per job.
        let existing = FetchDescriptor<MileageEntry>(
            predicate: #Predicate { $0.eventIdentifier == eventID }
        )
        guard ((try? context.fetchCount(existing)) ?? 0) == 0 else { return }

        // The day's previous stop with coordinates (by scheduled order).
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: record.scheduledStart)
        let jobStart = record.scheduledStart
        let descriptor = FetchDescriptor<WorkRecord>(
            predicate: #Predicate {
                $0.scheduledStart >= dayStart && $0.scheduledStart < jobStart
            },
            sortBy: [SortDescriptor(\.scheduledStart, order: .reverse)]
        )
        guard let previous = ((try? context.fetch(descriptor)) ?? [])
            .first(where: { $0.latitude != nil && $0.longitude != nil }),
              let fromLat = previous.latitude, let fromLon = previous.longitude else { return }

        let leg = await DriveTimeService.shared.travelLeg(
            from: CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon),
            to: CLLocationCoordinate2D(latitude: toLat, longitude: toLon)
        )
        guard leg.miles > 0 else { return }

        context.insert(MileageEntry(
            date: record.actualEnd ?? record.scheduledStart,
            fromLabel: previous.customerName.isEmpty ? previous.address : previous.customerName,
            toLabel: record.customerName.isEmpty ? record.address : record.customerName,
            miles: leg.miles,
            eventIdentifier: eventID
        ))
        try? context.save()
    }
}
