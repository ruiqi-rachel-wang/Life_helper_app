//  ExtractionService.swift
//
//  Orchestrates the whole "OCR text → ExtractionResult" pipeline:
//    1. Run the rule parser (free, exact) for amount / date / account.
//    2. Call the LLM for the things only it can do — summary, steps,
//       category, recurrence — passing the parser's facts as ground truth.
//    3. MERGE: the parser wins on amount / date / account (exact regex beats
//       a model's guess); the LLM provides everything else.
//
//  The one place we skip the model entirely is empty OCR — no text, no call,
//  no cost. (A broader "parser was confident, skip the LLM" path isn't real
//  yet: steps + summary always need the model. We don't fake a branch.)
//
//  Depends only on the `Extractor` protocol, so tests inject MockExtractor
//  and the real app injects OpenAIClient.
//

import Foundation

struct ExtractionService {
    let parser: RuleBasedParser
    let extractor: Extractor

    init(parser: RuleBasedParser = RuleBasedParser(),
         extractor: Extractor) {
        self.parser = parser
        self.extractor = extractor
    }

    func extract(from ocrText: String,
                 language: ExplainLanguage = .english) async throws -> ExtractionResult {
        // No text → nothing to do, and never spend an API call on a blank page.
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }

        let hints = parser.parse(ocrText)
        let llm = try await extractor.extract(text: ocrText, hints: hints, language: language)
        return merge(hints: hints, llm: llm)
    }

    // Parser facts beat the model on the exact fields; the model fills the rest.
    // Also flag any field the parser couldn't confirm as low-confidence so the
    // Review screen (Week 6) can nudge the user to check it.
    func merge(hints: RuleBasedParser.Hints, llm: ExtractionResult) -> ExtractionResult {
        var out = llm

        if let a = hints.amount { out.amount = a }
        if let c = hints.currency { out.currency = c }
        if let d = hints.dueDate { out.dueDate = d }
        if let n = hints.accountNumber { out.accountNumber = n }

        // If the parser didn't find the amount/date but the model supplied one,
        // mark it for review — those are the values worth a second glance.
        var lowConf = out.lowConfidenceFields
        if hints.amount == nil, out.amount != nil { lowConf.insert("amount") }
        if hints.dueDate == nil, out.dueDate != nil { lowConf.insert("dueDate") }
        out.lowConfidenceFields = lowConf

        return out
    }
}
