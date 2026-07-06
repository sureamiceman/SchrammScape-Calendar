//
//  WorkSummaryBuilder.swift
//  SchrammScape Calendar
//
//  Plain-text work summaries for texting/emailing customers.
//  No pricing — dates, jobs done, and durations only.
//

import Foundation

nonisolated enum WorkSummaryBuilder {

    /// One-line summary sent right after finishing a visit.
    static func singleVisit(_ record: WorkRecord) -> String {
        let day = record.scheduledStart.formatted(.dateTime.weekday(.abbreviated).month().day())
        var line = "Completed \(record.jobTitle) — \(day)"
        if let start = record.actualStart, let end = record.actualEnd {
            let range = "\(start.formatted(.dateTime.hour().minute()))–\(end.formatted(.dateTime.hour().minute()))"
            line += ", \(range)"
        }
        if let minutes = record.actualDurationMinutes {
            line += " (\(durationLabel(minutes)))"
        }
        line += "."
        for extra in record.extraServices {
            line += "\nAdded on site: \(extra)."
        }
        if !record.extraNotes.isEmpty {
            line += "\nExtra work: \(record.extraNotes)."
        }
        return line
    }

    /// Multi-visit summary for a customer over a date range.
    static func period(records: [WorkRecord], customerName: String, from: Date, to: Date) -> String {
        let sorted = records.sorted { $0.scheduledStart < $1.scheduledStart }
        var lines: [String] = []
        lines.append("SchrammScape Work Summary — \(customerName)")
        if let address = sorted.first?.address, !address.isEmpty {
            lines.append(address)
        }
        let range = "\(from.formatted(.dateTime.month().day())) – \(to.formatted(.dateTime.month().day().year()))"
        lines.append(range)
        lines.append("")

        var totalMinutes = 0
        for record in sorted {
            let day = record.scheduledStart.formatted(.dateTime.weekday(.abbreviated).month().day())
            var line = "• \(day) — \(record.jobTitle)"
            if let minutes = record.actualDurationMinutes ?? record.plannedDurationMinutes {
                line += " — \(durationLabel(minutes))"
                totalMinutes += minutes
            }
            lines.append(line)
            // Extra billing lines: jobs added on site and extra-work comments.
            for extra in record.extraServices {
                lines.append("   + \(extra) (added on site)")
            }
            if !record.extraNotes.isEmpty {
                lines.append("   Note: \(record.extraNotes)")
            }
        }

        lines.append("")
        let visits = "\(sorted.count) visit\(sorted.count == 1 ? "" : "s")"
        lines.append(totalMinutes > 0 ? "\(visits), total time \(durationLabel(totalMinutes))" : visits)
        return lines.joined(separator: "\n")
    }

    /// "45 min" or "3 hr 20 min".
    static func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
