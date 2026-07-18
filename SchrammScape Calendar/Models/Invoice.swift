//
//  Invoice.swift
//  SchrammScape Calendar
//
//  A numbered invoice built from completed visits (plus manual lines),
//  generated as a PDF for customers who need one (e.g. business write-offs).
//

import Foundation
import SwiftData

/// One billable line: a completed visit or a manually added charge.
struct InvoiceLine: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Visit date; nil for manual lines.
    var date: Date?
    var details: String
    var amount: Double
}

@Model
final class Invoice {
    var number: String
    var customerName: String
    var customerAddress: String
    var issueDate: Date
    var status: String = Status.open.rawValue
    var notes: String
    var lines: [InvoiceLine]
    var createdAt: Date

    enum Status: String {
        case open
        case paid
    }

    init(
        number: String = "",
        customerName: String = "",
        customerAddress: String = "",
        issueDate: Date = .now,
        status: Status = .open,
        notes: String = "",
        lines: [InvoiceLine] = [],
        createdAt: Date = .now
    ) {
        self.number = number
        self.customerName = customerName
        self.customerAddress = customerAddress
        self.issueDate = issueDate
        self.status = status.rawValue
        self.notes = notes
        self.lines = lines
        self.createdAt = createdAt
    }

    var statusValue: Status {
        get { Status(rawValue: status) ?? .open }
        set { status = newValue.rawValue }
    }

    var total: Double {
        lines.map(\.amount).reduce(0, +)
    }

    /// "INV-001" style: one greater than the highest existing number.
    static func nextNumber(context: ModelContext) -> String {
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let highest = invoices
            .compactMap { Int($0.number.split(separator: "-").last ?? "") }
            .max() ?? 0
        return String(format: "INV-%03d", highest + 1)
    }
}
