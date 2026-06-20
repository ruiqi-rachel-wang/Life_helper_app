//  ExtractionServiceTests.swift
//
//  Tests the orchestration + merge with a MockExtractor, so there is NO
//  network call and NO API cost. Verifies: empty OCR skips the model;
//  parser facts win over the model on amount/date; the model supplies
//  summary/steps/category; low-confidence flagging; errors propagate.
//

import Testing
import Foundation
@testable import Cuevi

struct ExtractionServiceTests {

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    // A rich fake LLM result to merge against.
    private func stub() -> ExtractionResult {
        ExtractionResult(
            documentType: "Utility bill",
            sender: "Con Edison",
            amount: dec("999.99"),                 // deliberately wrong; parser should win
            currency: "USD",
            dueDate: DateComponents(calendar: .current, year: 2030, month: 1, day: 1).date,
            category: .utility,
            summary: "This is your electricity bill.",
            steps: ["Open the Con Edison app.", "Pay the balance.", "Save the receipt."],
            confidence: 0.9
        )
    }

    // MARK: empty-OCR skip (the one real "don't call the model" path)

    @Test func emptyOCRSkipsModel() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        let result = try await service.extract(from: "")
        #expect(result.isEmpty)
        #expect(mock.callCount == 0)
    }

    @Test func whitespaceOnlySkipsModel() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        _ = try await service.extract(from: "   \n\t ")
        #expect(mock.callCount == 0)
    }

    @Test func nonEmptyOCRCallsModelOnce() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        _ = try await service.extract(from: "Amount due: $86.42")
        #expect(mock.callCount == 1)
    }

    // MARK: merge precedence (single item)

    @Test func parserAmountWinsOverModel() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Amount due: $86.42")
        #expect(r.first?.amount == dec("86.42"))      // not the model's 999.99
    }

    @Test func parserDateWinsOverModel() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Payment is due on 06/15/2026.")
        #expect(r.first?.dueDate != nil)
        #expect(ymd(r.first!.dueDate!) == (2026, 6, 15))   // not the model's 2030
    }

    @Test func modelSuppliesSummaryStepsAndCategory() async throws {
        let mock = MockExtractor(stub: [stub()])
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Amount due: $86.42").first
        #expect(r?.summary == "This is your electricity bill.")
        #expect(r?.steps.count == 3)
        #expect(r?.category == .utility)
        #expect(r?.sender == "Con Edison")
    }

    // MARK: multi-item — return all, no whole-page merge

    @Test func multipleItemsReturnedAndParserMergeSkipped() async throws {
        let a = ExtractionResult(title: "Neurology appt", amount: dec("10.00"))
        let b = ExtractionResult(title: "CT scan", amount: dec("20.00"))
        let mock = MockExtractor(stub: [a, b])
        let service = ExtractionService(extractor: mock)
        // OCR text has a single "$5" — must NOT overwrite either item's amount.
        let r = try await service.extract(from: "Amount due: $5.00 across visits")
        #expect(r.count == 2)
        #expect(r.map(\.title) == ["Neurology appt", "CT scan"])
        #expect(r[0].amount == dec("10.00"))   // not the page's $5
        #expect(r[1].amount == dec("20.00"))
    }

    // MARK: low-confidence flagging

    @Test func modelAmountWithoutParserAmountIsFlagged() {
        // Parser found nothing; model supplied an amount → flag it for review.
        let service = ExtractionService(extractor: MockExtractor())
        let merged = service.merge(hints: RuleBasedParser.Hints(),
                                   llm: ExtractionResult(amount: dec("50.00")))
        #expect(merged.lowConfidenceFields.contains("amount"))
    }

    @Test func parserConfirmedAmountIsNotFlagged() {
        let service = ExtractionService(extractor: MockExtractor())
        let hints = RuleBasedParser.Hints(amount: dec("86.42"))
        let merged = service.merge(hints: hints, llm: ExtractionResult(amount: dec("86.42")))
        #expect(!merged.lowConfidenceFields.contains("amount"))
    }

    // MARK: amount — credit / disagreement (don't show a credit as owed)

    @Test func creditBalanceNotShownAsOwed() {
        // Regex found "$120.60" (a positive lunch-account balance); the model
        // judged nothing is owed (nil). Trust the model, but flag for review.
        let service = ExtractionService(extractor: MockExtractor())
        let merged = service.merge(hints: RuleBasedParser.Hints(amount: dec("120.60")),
                                   llm: ExtractionResult(amount: nil))
        #expect(merged.amount == nil)
        #expect(merged.lowConfidenceFields.contains("amount"))
    }

    @Test func agreedAmountUsesRegexDigitsAndIsNotFlagged() {
        let service = ExtractionService(extractor: MockExtractor())
        let merged = service.merge(hints: RuleBasedParser.Hints(amount: dec("86.42")),
                                   llm: ExtractionResult(amount: dec("86.42")))
        #expect(merged.amount == dec("86.42"))
        #expect(!merged.lowConfidenceFields.contains("amount"))
    }

    @Test func disagreedAmountKeepsRegexButFlags() {
        let service = ExtractionService(extractor: MockExtractor())
        let merged = service.merge(hints: RuleBasedParser.Hints(amount: dec("86.42")),
                                   llm: ExtractionResult(amount: dec("84.62")))
        #expect(merged.amount == dec("86.42"))   // exact regex digits win
        #expect(merged.lowConfidenceFields.contains("amount"))
    }

    // MARK: due date — preserve the model's TIME on the same day

    @Test func timedDuePreservesModelTimeOnSameDay() {
        let service = ExtractionService(extractor: MockExtractor())
        let day = DateComponents(calendar: .current, year: 2026, month: 6, day: 25).date!
        let dayTime = DateComponents(calendar: .current, year: 2026, month: 6, day: 25, hour: 8, minute: 5).date!
        let merged = service.merge(hints: RuleBasedParser.Hints(dueDate: day),
                                   llm: ExtractionResult(dueDate: dayTime, dueHasTime: true))
        #expect(merged.dueHasTime == true)
        let c = Calendar.current.dateComponents([.hour, .minute], from: merged.dueDate!)
        #expect(c.hour == 8 && c.minute == 5)    // not midnight
    }

    @Test func timedDueResetsWhenModelTimeIsDifferentDay() {
        let service = ExtractionService(extractor: MockExtractor())
        let day25 = DateComponents(calendar: .current, year: 2026, month: 6, day: 25).date!
        let day20Time = DateComponents(calendar: .current, year: 2026, month: 6, day: 20, hour: 8, minute: 5).date!
        let merged = service.merge(hints: RuleBasedParser.Hints(dueDate: day25),
                                   llm: ExtractionResult(dueDate: day20Time, dueHasTime: true))
        #expect(merged.dueHasTime == false)      // regex date has no time
        #expect(ymd(merged.dueDate!) == (2026, 6, 25))
    }

    // MARK: errors

    @Test func modelErrorPropagates() async {
        struct Boom: Error {}
        let mock = MockExtractor(error: Boom())
        let service = ExtractionService(extractor: mock)
        await #expect(throws: Boom.self) {
            _ = try await service.extract(from: "Amount due: $86.42")
        }
    }
}
