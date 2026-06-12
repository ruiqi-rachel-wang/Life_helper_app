//  Extractor.swift
//
//  The seam between "our code" and "the AI". Everything that turns OCR text
//  into an ExtractionResult conforms to `Extractor`:
//   • OpenAIClient   — the real GPT-4o-mini call (OpenAIClient.swift)
//   • MockExtractor  — canned results for unit tests + SwiftUI previews (no
//                      network, no cost)
//
//  Because both sides of the seam share this protocol, swapping the direct
//  OpenAI call for the Cloudflare Worker later is a one-line change, and the
//  whole pipeline is testable for free.
//

import Foundation

// Which language the AI writes its explanation/steps in. Defaults to English
// in Week 5 (Settings is still a stub); the real Settings picker that drives
// this — and defaults to device language — lands in Week 8. UI chrome stays
// English; only the AI's prose respects this.
nonisolated enum ExplainLanguage: String, Codable, CaseIterable {
    case english, chinese, spanish

    // How we name the language TO the model in the prompt.
    var promptName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Simplified Chinese"
        case .spanish: return "Spanish"
        }
    }
}

nonisolated protocol Extractor {
    /// Turn raw OCR text into a structured ExtractionResult.
    /// - Parameters:
    ///   - text: the raw OCR output.
    ///   - hints: exact fields the rule parser already found (passed to the
    ///     model as ground truth so it doesn't re-guess the amount/date).
    ///   - language: the language the summary + steps should be written in.
    /// Returns one ExtractionResult per action item found. Most documents yield
    /// exactly one; a list (e.g. several appointments) yields several.
    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult]
}

// A fake Extractor for tests + previews. Returns a canned result, can be told
// to throw, and records whether it was actually called (so a test can prove
// ExtractionService skipped the model on empty OCR).
nonisolated final class MockExtractor: Extractor {
    var stub: [ExtractionResult]
    var error: Error?
    private(set) var callCount = 0
    private(set) var lastText: String?

    init(stub: [ExtractionResult] = [], error: Error? = nil) {
        self.stub = stub
        self.error = error
    }

    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult] {
        callCount += 1
        lastText = text
        if let error { throw error }
        return stub
    }
}
