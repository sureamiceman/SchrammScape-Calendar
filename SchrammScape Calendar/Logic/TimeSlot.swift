//
//  TimeSlot.swift
//  SchrammScape Calendar
//
//  Time helpers ported from app.js: 6 AM start, 15-minute increments.
//

import Foundation

nonisolated enum TimeSlot {
    static let startMinutes = 6 * 60      // 6:00 AM
    static let maxStartMinutes = 20 * 60  // 8:00 PM
    static let increment = 15

    /// Selectable start times (6:00 AM through 8:00 PM).
    static let startSlots: [String] = stride(from: startMinutes, through: maxStartMinutes, by: increment)
        .map(string(fromMinutes:))

    /// Selectable end times (6:15 AM through 9:00 PM).
    static let endSlots: [String] = stride(from: startMinutes + increment, through: 21 * 60, by: increment)
        .map(string(fromMinutes:))

    static func minutes(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    static func string(fromMinutes total: Int) -> String {
        let t = max(0, total)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    static func addMinutes(to hhmm: String, minutes value: Int) -> String {
        guard let base = minutes(from: hhmm) else { return "" }
        return string(fromMinutes: base + value)
    }

    /// Rounds a time up to the next 15-minute slot, clamped to the valid start range.
    static func roundedUpStart(_ hhmm: String) -> String? {
        guard let mins = minutes(from: hhmm) else { return nil }
        let up = Int((Double(mins) / Double(increment)).rounded(.up)) * increment
        guard up >= startMinutes, up <= maxStartMinutes else { return nil }
        return string(fromMinutes: up)
    }

    /// A localized "h:mm a" label for display.
    static func display(_ hhmm: String) -> String {
        guard let mins = minutes(from: hhmm) else { return "—" }
        var comps = DateComponents()
        comps.hour = mins / 60
        comps.minute = mins % 60
        guard let date = Calendar.current.date(from: comps) else { return hhmm }
        return date.formatted(.dateTime.hour().minute())
    }

    /// Combines a calendar day with a "HH:mm" time into a concrete Date.
    static func date(day: Date, hhmm: String) -> Date? {
        guard let mins = minutes(from: hhmm) else { return nil }
        return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: day)
    }

    /// Parses a duration label ("60", "90", "TBD") into minutes.
    static func parseDurationMinutes(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.lowercased() == "tbd" { return nil }
        guard let value = Double(t), value > 0 else { return nil }
        return Int(value.rounded())
    }
}
