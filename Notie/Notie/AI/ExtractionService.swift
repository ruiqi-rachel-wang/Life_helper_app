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

nonisolated struct ExtractionService {
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

    // The parser reads exact values; the model judges meaning. Merge keeps the
    // parser's precision WITHOUT letting it override the model's judgment about
    // whether money is owed or whether a date carries a time. Disagreements are
    // flagged low-confidence so the Review screen (Week 6) can nudge a check.
    func merge(hints: RuleBasedParser.Hints, llm: ExtractionResult) -> ExtractionResult {
        var out = llm
        var lowConf = out.lowConfidenceFields

        // AMOUNT: the regex reads exact digits but can't tell "owed" from a
        // credit / paid receipt / positive balance — the model can. So respect
        // the model's call on WHETHER money is owed; use the regex only to
        // sharpen the number when the model agrees there is one.
        switch (hints.amount, llm.amount) {
        case let (parsed?, model?):
            out.amount = parsed                          // exact digits from regex
            if parsed != model { lowConf.insert("amount") }   // they disagree → check
        case (_?, nil):
            // Regex found a number but the model said nothing is owed (a credit,
            // a paid receipt, a positive balance). Trust the model; just flag it
            // so the user can confirm it really isn't owed.
            out.amount = nil
            lowConf.insert("amount")
        case (nil, _?):
            lowConf.insert("amount")                     // only the model found it
        case (nil, nil):
            break
        }
        if let c = hints.currency, out.amount != nil { out.currency = c }

        // DUE DATE: the regex date wins for the DAY, but preserve the model's
        // TIME when it lands on that same day (the regex only knows the date, not
        // the 8:05 AM departure). Otherwise a regex date has no time.
        if let parsedDue = hints.dueDate {
            let modelHadSameDayTime = out.dueHasTime
                && out.dueDate.map { Calendar.current.isDate($0, inSameDayAs: parsedDue) } == true
            if !modelHadSameDayTime {
                out.dueDate = parsedDue
                out.dueHasTime = false
            }
        } else if out.dueDate != nil {
            lowConf.insert("dueDate")                     // only the model found a date
        }

        if let n = hints.accountNumber { out.accountNumber = n }

        out.lowConfidenceFields = lowConf
        return out
    }
}
