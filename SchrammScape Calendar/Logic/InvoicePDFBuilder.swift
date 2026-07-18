//
//  InvoicePDFBuilder.swift
//  SchrammScape Calendar
//
//  Renders an Invoice to a US-Letter PDF using a SwiftUI template.
//  Letterhead details are user-editable (Invoice Settings in the Billing tab).
//

import SwiftUI

/// User-editable letterhead, stored in UserDefaults (edited via Invoice Settings).
enum BusinessInfo {
    static let nameKey = "businessName"
    static let addressKey = "businessAddress"
    static let phoneKey = "businessPhone"
    static let emailKey = "businessEmail"

    static var name: String {
        let value = UserDefaults.standard.string(forKey: nameKey) ?? ""
        return value.isEmpty ? "SchrammScape" : value
    }
    static var address: String { UserDefaults.standard.string(forKey: addressKey) ?? "" }
    static var phone: String { UserDefaults.standard.string(forKey: phoneKey) ?? "" }
    static var email: String { UserDefaults.standard.string(forKey: emailKey) ?? "" }
}

@MainActor
enum InvoicePDFBuilder {

    /// Renders the invoice to a single US-Letter PDF page in the temp
    /// directory, returning its URL for sharing.
    static func makePDF(invoice: Invoice) -> URL? {
        let pageSize = CGSize(width: 612, height: 792)  // US Letter in points
        let renderer = ImageRenderer(
            content: InvoiceDocumentView(invoice: invoice)
                .frame(width: pageSize.width, height: pageSize.height)
        )
        renderer.proposedSize = ProposedViewSize(pageSize)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(invoice.number).pdf")
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        renderer.render { _, renderView in
            pdfContext.beginPDFPage(nil)
            renderView(pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
        return url
    }
}

// MARK: - The printed template

struct InvoiceDocumentView: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            billTo
            lineTable
            Spacer(minLength: 0)
            footer
        }
        .padding(48)
        .foregroundStyle(.black)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BusinessInfo.name)
                        .font(.title2.bold())
                    if !BusinessInfo.address.isEmpty {
                        Text(BusinessInfo.address).font(.caption)
                    }
                    if !BusinessInfo.phone.isEmpty {
                        Text(BusinessInfo.phone).font(.caption)
                    }
                    if !BusinessInfo.email.isEmpty {
                        Text(BusinessInfo.email).font(.caption)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("INVOICE")
                    .font(.title.bold())
                Text(invoice.number)
                    .font(.headline)
                Text(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
            }
        }
    }

    private var billTo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BILL TO")
                .font(.caption.bold())
                .foregroundStyle(.gray)
            Text(invoice.customerName)
                .font(.headline)
            if !invoice.customerAddress.isEmpty {
                Text(invoice.customerAddress)
                    .font(.subheadline)
            }
        }
    }

    private var lineTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DATE").frame(width: 90, alignment: .leading)
                Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                Text("AMOUNT").frame(width: 90, alignment: .trailing)
            }
            .font(.caption.bold())
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1) }

            ForEach(invoice.lines) { line in
                HStack(alignment: .top) {
                    Text(line.date.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "—")
                        .frame(width: 90, alignment: .leading)
                    Text(line.details)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(line.amount.formatted(.currency(code: "USD")))
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.footnote)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().frame(height: 0.5).foregroundStyle(.gray.opacity(0.4))
                }
            }

            HStack {
                Spacer()
                Text("TOTAL")
                    .font(.headline)
                Text(invoice.total.formatted(.currency(code: "USD")))
                    .font(.headline)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.top, 10)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !invoice.notes.isEmpty {
                Text("Notes: \(invoice.notes)")
                    .font(.footnote)
            }
            Text("Payment terms: Due on receipt")
                .font(.footnote.bold())
            Text("Thank you for your business!")
                .font(.footnote)
                .foregroundStyle(.gray)
        }
    }
}
