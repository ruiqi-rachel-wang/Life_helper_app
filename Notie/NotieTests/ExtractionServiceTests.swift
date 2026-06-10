//  ExtractionServiceTests.swift
//
//  Tests the orchestration + merge with a MockExtractor, so there is NO
//  network call and NO API cost. Verifies: empty OCR skips the model;
//  parser facts win over the model on amount/date; the model supplies
//  summary/steps/category; low-confidence flagging; errors propagate.
//

import Testing
import Foundation
@testable import Notie

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
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        let result = try await service.extract(from: "")
        #expect(result == .empty)
        #expect(mock.callCount == 0)
    }

    @Test func whitespaceOnlySkipsModel() async throws {
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        _ = try await service.extract(from: "   \n\t ")
        #expect(mock.callCount == 0)
    }

    @Test func nonEmptyOCRCallsModelOnce() async throws {
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        _ = try await service.extract(from: "Amount due: $86.42")
        #expect(mock.callCount == 1)
    }

    // MARK: merge precedence

    @Test func parserAmountWinsOverModel() async throws {
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Amount due: $86.42")
        #expect(r.amount == dec("86.42"))      // not the model's 999.99
    }

    @Test func parserDateWinsOverModel() async throws {
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Payment is due on 06/15/2026.")
        #expect(r.dueDate != nil)
        #expect(ymd(r.dueDate!) == (2026, 6, 15))   // not the model's 2030
    }

    @Test func modelSuppliesSummaryStepsAndCategory() async throws {
        let mock = MockExtractor(stub: stub())
        let service = ExtractionService(extractor: mock)
        let r = try await service.extract(from: "Amount due: $86.42")
        #expect(r.summary == "This is your electricity bill.")
        #expect(r.steps.count == 3)
        #expect(r.category == .utility)
        #expect(r.sender == "Con Edison")
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
