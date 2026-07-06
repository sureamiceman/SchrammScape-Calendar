//
//  CSVSupport.swift
//  SchrammScape Calendar
//
//  CSV import/export ported from app.js (parseDelimitedText / parseCustomerRows /
//  buildReferenceCsv). Recognizes Customer, Location/Address, Job/Title, Duration.
//

import Foundation

struct ParsedCustomer: Sendable {
    var name: String
    var address: String
    var jobTitle: String
    var durationLabel: String
    var dayOfWeek: String = ""
    var mower: String = ""
    var details: String = ""
    var phone: String = ""
    var email: String = ""
    var height: String = ""
    var visitIntervalWeeks: Int = 1

    /// Builds a SwiftData model object from this parsed row.
    func makeCustomer(sortOrder: Int) -> Customer {
        Customer(
            name: name,
            address: address,
            jobTitle: jobTitle,
            durationLabel: durationLabel,
            sortOrder: sortOrder,
            dayOfWeek: dayOfWeek,
            mower: mower,
            details: details,
            phone: phone,
            email: email,
            height: height,
            visitIntervalWeeks: visitIntervalWeeks
        )
    }
}

nonisolated enum CSVSupport {

    static func parseCustomers(_ text: String) -> [ParsedCustomer] {
        let rows = parseDelimited(text)
        guard rows.count >= 2 else { return [] }

        let headers = rows[0].map(normalizeHeader)
        let nameIdx = headerIndex(headers, ["customer", "customername", "name", "client"])
        let locIdx = headerIndex(headers, ["location", "address", "site", "jobsite"])
        let jobIdx = headerIndex(headers, ["job", "jobtitle", "title", "service"])
        let durIdx = headerIndex(headers, ["duration", "durationminutes", "minutes", "mins"])
        let dowIdx = headerIndex(headers, ["dow", "day", "dayofweek"])
        let mowerIdx = headerIndex(headers, ["mower", "machine"])
        let detailsIdx = headerIndex(headers, ["details", "notes", "note", "comments"])
        let phoneIdx = headerIndex(headers, ["phone", "phonenumber", "tel", "telephone"])
        let emailIdx = headerIndex(headers, ["email", "emailaddress", "mail"])
        let freqIdx = headerIndex(headers, ["frequency", "visitweeks", "cadence"])
        let heightIdx = headerIndex(headers, ["height", "cuttingheight", "cutheight"])

        // Need at least a name or a location column to be meaningful.
        guard nameIdx != nil || locIdx != nil else { return [] }

        return rows.dropFirst().compactMap { row -> ParsedCustomer? in
            func cell(_ idx: Int?) -> String {
                guard let idx, idx >= 0, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }
            let name = cell(nameIdx)
            let loc = cell(locIdx)
            let jobCell = cell(jobIdx)
            let dur = cell(durIdx)
            if name.isEmpty && loc.isEmpty && jobCell.isEmpty && dur.isEmpty { return nil }
            let title = jobCell.isEmpty ? (name.isEmpty ? loc : name) : jobCell
            return ParsedCustomer(
                name: name,
                address: loc,
                jobTitle: title,
                durationLabel: dur,
                dayOfWeek: cell(dowIdx).uppercased(),
                mower: cell(mowerIdx),
                details: cell(detailsIdx),
                phone: cell(phoneIdx),
                email: cell(emailIdx),
                height: cell(heightIdx),
                visitIntervalWeeks: parseFrequency(cell(freqIdx))
            )
        }
    }

    static func exportCSV(_ customers: [Customer]) -> String {
        var rows: [[String]] = [["Customer", "Address", "Title", "duration", "DOW", "Mower", "Details", "Phone", "Email", "Height", "Frequency"]]
        for c in customers {
            rows.append([c.name, c.address, c.jobTitle, c.durationLabel, c.dayOfWeek, c.mower, c.details, c.phone, c.email, c.height, String(c.visitIntervalWeeks)])
        }
        return rows.map { $0.map(escapeCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Delimited parsing

    static func parseDelimited(_ text: String) -> [[String]] {
        let src = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let delim = detectDelimiter(src)
        var rows: [[String]] = []
        var current = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(src)
        var i = 0

        func commitRow() {
            row.append(current)
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(row)
            }
            row = []
            current = ""
        }

        while i < chars.count {
            let ch = chars[i]
            let nx: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if ch == "\"" {
                if inQuotes, nx == "\"" { current.append("\""); i += 1 }
                else { inQuotes.toggle() }
                i += 1
                continue
            }
            if !inQuotes, ch == delim {
                row.append(current); current = ""; i += 1
                continue
            }
            if !inQuotes, ch == "\n" || ch == "\r" {
                if ch == "\r", nx == "\n" { i += 1 }
                commitRow()
                i += 1
                continue
            }
            current.append(ch)
            i += 1
        }
        commitRow()
        return rows
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
        let commas = firstLine.filter { $0 == "," }.count
        let tabs = firstLine.filter { $0 == "\t" }.count
        let semis = firstLine.filter { $0 == ";" }.count
        if tabs >= commas && tabs >= semis { return "\t" }
        if semis > commas { return ";" }
        return ","
    }

    /// "2", "Bi-Weekly", "biweekly" → weeks between visits; blank/unknown → 1.
    private static func parseFrequency(_ value: String) -> Int {
        let t = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let weeks = Int(t), weeks >= 1 { return weeks }
        if t.contains("bi") { return 2 }
        if t.contains("month") { return 4 }
        return 1
    }

    private static func normalizeHeader(_ v: String) -> String {
        String(v.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func headerIndex(_ headers: [String], _ aliases: [String]) -> Int? {
        headers.firstIndex { aliases.contains($0) }
    }

    private static func escapeCell(_ v: String) -> String {
        if v.contains(where: { $0 == "\"" || $0 == "," || $0 == "\r" || $0 == "\n" }) {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
