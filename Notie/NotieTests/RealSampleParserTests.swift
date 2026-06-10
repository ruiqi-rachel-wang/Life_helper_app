//  RealSampleParserTests.swift
//
//  Runs the rule parser against the REAL Week-4 OCR samples (see
//  sample_documents.md) plus two standard bills. Documents exactly what the
//  free parser is expected to nail vs. what it deliberately defers to the LLM
//  (ambiguous dates with no cue). Pure/local — no network, no cost.
//

import Testing
import Foundation
@testable import Notie

struct RealSampleParserTests {
    let parser = RuleBasedParser()
    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }
    private func ymd(_ d: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d); return (c.year!, c.month!, c.day!)
    }

    // 1. Flight: two dates (sent June 3 vs departure 6/25) → the "departure"
    //    cue must beat the email's sent-date (the old first-date rule failed).
    @Test func flightPicksDepartureNotSentDate() {
        let text = """
        Ticket Itinerary and Receipt for Confirmation A4C33C
        United Airlines  Wednesday, June 3, 2026 at 10:16 AM
        Departure: Thu 06/25/2026 8:05 AM (2 hrs 39 mins)
        LGA 8:05 AM Thu 6/25/2026  ORD 9:44 AM Thu 6/25/2026
        """
        let h = parser.parse(text)
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 6, 25))
    }

    // 2. Costco receipt: amount with no "$" (trailing-cents rule), and the
    //    "expires" cue picks the Rx expiry over the earlier invoice dates.
    @Test func costcoTotalAndRxExpiry() {
        let text = """
        COSTCO OPTICAL
        INVOICE DATE 8/30/25  INVOICE NO. 6166840
        Rx WRITTEN 8/27/25  Rx EXPIRES 8/27/26
        SUBTOTAL 232.98  TAX 0.00  TOTAL 232.98  Visa 232.98
        """
        let h = parser.parse(text)
        #expect(h.amount == dec("232.98"))
        #expect(h.currency == "USD")
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 8, 27))
    }

    // 3. GNPS: "Balance $120.60" is a credit; "Customer ID" now parses.
    @Test func gnpsBalanceAndCustomerID() {
        let text = """
        GNPS Positive Lunch Account Balance
        Student Name: Siyue Wang  Customer ID: 300012817  Balance $120.60
        """
        let h = parser.parse(text)
        #expect(h.amount == dec("120.60"))
        #expect(h.accountNumber == "300012817")
    }

    // 4. GEICO: two dates (sent June 5 vs appointment 06/24). The "appointment"
    //    cue on the line above "Date:" lets the parser pick 06/24 over the email
    //    sent-date — and there's no amount on an appointment notice.
    @Test func geicoPicksAppointmentDate() {
        let text = """
        GEICO  Friday, June 5, 2026 at 3:45 PM
        Your GEICO vehicle appointment
        Date: 06/24/2026  Time: 11:00 AM
        Location: Northern Boulevard Collision-XD
        """
        let h = parser.parse(text)
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 6, 24))
        #expect(h.amount == nil)
    }

    // 6. Standard utility bill — the classic case the parser should fully nail.
    @Test func standardConEdisonBill() {
        let text = """
        Con Edison — Your Energy Bill
        Account number: 12-3456-7890-0001
        Billing period: May 1 - May 31, 2026
        Amount due: $86.42
        Payment due date: June 15, 2026
        """
        let h = parser.parse(text)
        #expect(h.amount == dec("86.42"))
        #expect(h.currency == "USD")
        #expect(h.accountNumber == "12-3456-7890-0001")
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 6, 15))
    }

    // 8. Standard IRS notice — amount + "pay by" date.
    @Test func standardIRSNotice() {
        let text = """
        Internal Revenue Service  Notice CP14
        Notice date: June 2, 2026
        Amount due: $1,247.00
        Pay by July 1, 2026 to avoid additional interest and penalties.
        """
        let h = parser.parse(text)
        #expect(h.amount == dec("1247.00"))
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 7, 1))
    }
}
