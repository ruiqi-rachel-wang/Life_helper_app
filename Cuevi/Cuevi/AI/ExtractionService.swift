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
                 language: ExplainLanguage = .english) async throws -> [ExtractionResult] {
        // No text → nothing to do, and never spend an API call on a blank page.
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let hints = parser.parse(ocrText)
        let items = try await extractor.extract(text: ocrText, hints: hints, language: language)
        // The regex hints describe the WHOLE page, so merging them only makes
        // sense for a single item. For a multi-item document, trust the model's
        // per-item amount/date — it did the splitting.
        if items.count == 1 {
            return [merge(hints: hints, llm: items[0])]
        }
        return items
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

        // DUE DATE: the model decides WHICH date is the deadline (it reads the
        // context — exam date vs. "submit within 90 days" vs. the date the email
        // was sent); the regex only sharpens a printed date the model agrees with.
        if let parsedDue = hints.dueDate {
            if let modelDue = out.dueDate {
                let sameDay = Calendar.current.isDate(modelDue, inSameDayAs: parsedDue)
                if llm.lowConfidenceFields.contains("dueDate") {
                    // The model COMPUTED the deadline (e.g. exam + 90 days). A raw
                    // date the regex grabbed off the page is some OTHER date — keep
                    // the model's computed deadline, just flag it for a quick check.
                    lowConf.insert("dueDate")
                } else if sameDay {
                    // Same day → keep the model's value so a flight/appointment TIME
                    // it found (8:05 AM) survives; the regex only knew the day.
                } else {
                    // A plainly-printed deadline the model didn't flag: the regex
                    // digits are exact, so prefer them — but the model disagreed on
                    // the day, so flag it.
                    out.dueDate = parsedDue
                    out.dueHasTime = false
                    lowConf.insert("dueDate")
                }
            } else {
                out.dueDate = parsedDue                    // model had none; use the printed date
                out.dueHasTime = false
            }
        } else if out.dueDate != nil {
            lowConf.insert("dueDate")                     // only the model found a date
        }

        // Prefer the MODEL's actionable id (it's prompted to pick the one you act on —
        // e.g. a ticket's summons number over the plate). Use the regex hint only as a
        // fallback when the model didn't return one.
        if (out.accountNumber ?? "").isEmpty, let n = hints.accountNumber { out.accountNumber = n }

        out.lowConfidenceFields = lowConf
        return out
    }
}
