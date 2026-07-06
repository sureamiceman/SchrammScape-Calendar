//
//  ICSBuilder.swift
//  SchrammScape Calendar
//
//  .ics generation ported from app.js buildICS().
//

import Foundation

nonisolated enum ICSBuilder {
    static func build(
        events: [ScheduledEvent],
        calendarName: String = "Schrammscape",
        timeZone: String = "America/New_York"
    ) -> String {
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0",
            "PRODID:-//SchrammScape Calendar//Weekly Work Schedule//EN",
            "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escape(calendarName))",
            "X-WR-TIMEZONE:\(escape(timeZone))",
        ]
        let stamp = utcStamp(Date())
        for (i, event) in events.enumerated() {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(uid(event, i))")
            lines.append("DTSTAMP:\(stamp)")
            lines.append("DTSTART;TZID=\(escape(timeZone)):\(localStamp(event.start))")
            lines.append("DTEND;TZID=\(escape(timeZone)):\(localStamp(event.end))")
            lines.append("SUMMARY:\(escape(event.title))")
            if !event.location.isEmpty { lines.append("LOCATION:\(escape(event.location))") }
            let descParts = [event.notes, event.location.isEmpty ? "" : "Location: \(event.location)"]
                .filter { !$0.isEmpty }
            if !descParts.isEmpty {
                lines.append("DESCRIPTION:\(escape(descParts.joined(separator: "\n")))")
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func uid(_ event: ScheduledEvent, _ index: Int) -> String {
        let slug = event.title.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
        return "\(String(slug))-\(index)@schrammscape.local"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    private static func localStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
