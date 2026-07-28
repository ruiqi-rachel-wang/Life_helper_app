//  RuleBasedParserTests.swift
//
//  Exercises the free, deterministic extraction: amount, currency, due date,
//  account number. No network, no cost — runs in ~milliseconds with Cmd+U.
//

import Testing
import Foundation
@testable import Tadah

struct RuleBasedParserTests {
    let parser = RuleBasedParser()

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    // MARK: amount

    @Test func plainDollarAmount() {
        #expect(parser.parse("Pay $86.42").amount == dec("86.42"))
    }

    @Test func amountWithThousandsSeparator() {
        #expect(parser.parse("Amount due: $1,234.56").amount == dec("1234.56"))
    }

    @Test func amountWithoutCents() {
        #expect(parser.parse("Total Due $90").amount == dec("90"))
    }

    @Test func amountWithLeadingCurrencyCode() {
        let h = parser.parse("Balance: USD 86.42")
        #expect(h.amount == dec("86.42"))
        #expect(h.currency == "USD")
    }

    @Test func amountWithTrailingCurrencyCode() {
        let h = parser.parse("Rent 1,200.00 USD this month")
        #expect(h.amount == dec("1200.00"))
        #expect(h.currency == "USD")
    }

    @Test func keywordAmountBeatsOtherNumbers() {
        // Late fee is bigger, but the amount-due keyword should win.
        let text = "Late fee if missed: $300.00. Amount due: $86.42."
        #expect(parser.parse(text).amount == dec("86.42"))
    }

    @Test func largestAmountWhenNoKeyword() {
        let text = "Line one $10.00\nLine two $250.00\nLine three $5.00"
        #expect(parser.parse(text).amount == dec("250.00"))
    }

    @Test func noAmountIsNil() {
        #expect(parser.parse("Dear resident, please call our office.").amount == nil)
    }

    @Test func yearsAreNotTreatedAsAmounts() {
        #expect(parser.parse("Issued in 2026 to all tenants.").amount == nil)
    }

    // MARK: currency

    @Test func dollarSignIsUSD() {
        #expect(parser.parse("Pay $5.00").currency == "USD")
    }

    @Test func euroSignIsEUR() {
        let h = parser.parse("Total €90")
        #expect(h.currency == "EUR")
        #expect(h.amount == dec("90"))
    }

    @Test func poundSignIsGBP() {
        let h = parser.parse("Owed £45.50")
        #expect(h.currency == "GBP")
        #expect(h.amount == dec("45.50"))
    }

    @Test func noCurrencyWhenNoAmount() {
        #expect(parser.parse("Thank you.").currency == nil)
    }

    // MARK: due date

    @Test func slashDateWithDueContext() {
        let d = parser.parse("Due date: 06/15/2026").dueDate
        #expect(d != nil)
        #expect(ymd(d!) == (2026, 6, 15))
    }

    @Test func writtenMonthDate() {
        let d = parser.parse("Please pay by June 15, 2026 to avoid a fee.").dueDate
        #expect(d != nil)
        #expect(ymd(d!) == (2026, 6, 15))
    }

    @Test func prefersDueContextDateOverEarlierDate() {
        let text = "Statement date: 05/01/2026. Payment is due on 06/30/2026."
        let d = parser.parse(text).dueDate
        #expect(d != nil)
        #expect(ymd(d!) == (2026, 6, 30))
    }

    @Test func noDateIsNil() {
        #expect(parser.parse("Thank you for your business.").dueDate == nil)
    }

    // MARK: account / reference number

    @Test func accountNumberLabeled() {
        #expect(parser.parse("Account Number: 1234567890").accountNumber == "1234567890")
    }

    @Test func acctWithHashAndDash() {
        #expect(parser.parse("Acct #: 12-3456").accountNumber == "12-3456")
    }

    @Test func violationNumber() {
        #expect(parser.parse("Violation #1234567890 must be paid").accountNumber == "1234567890")
    }

    @Test func noAccountNumberIsNil() {
        #expect(parser.parse("Please pay promptly.").accountNumber == nil)
    }

    // MARK: whole-document behavior

    @Test func emptyTextYieldsEmptyHints() {
        #expect(parser.parse("").isEmpty)
        #expect(parser.parse("   \n  \t ").isEmpty)
    }

    @Test func realisticBillFillsEverything() {
        let bill = """
        CON EDISON
        Account Number: 1234567890
        Your electricity charges for this period.
        Amount due: $86.42
        Due date: 06/15/2026
        """
        let h = parser.parse(bill)
        #expect(h.amount == dec("86.42"))
        #expect(h.currency == "USD")
        #expect(h.accountNumber == "1234567890")
        #expect(h.dueDate != nil)
        #expect(ymd(h.dueDate!) == (2026, 6, 15))
    }
}
