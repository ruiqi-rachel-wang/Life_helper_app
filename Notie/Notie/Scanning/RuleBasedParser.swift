//  RuleBasedParser.swift
//
//  Step 2 of the pipeline (after Vision OCR): pull the EXACT, deterministic
//  fields out of raw text with regex — amount, currency, due date, account
//  number. Free, instant, and more reliable than an LLM for these specific
//  values (a model can fumble "$1,234.56"; a regex won't).
//
//  It does NOT try to summarize or write steps — that needs the LLM. The two
//  feed into ExtractionService, which prefers these parser facts on merge.
//
//  UI-free (Scanning/ has no SwiftUI). Pure input → output, so it's heavily
//  unit-tested (RuleBasedParserTests).
//

import Foundation

nonisolated struct RuleBasedParser {

    // The exact fields regex can find. All optional — a friendly letter with
    // no money or date yields an all-nil Hints, and that's fine.
    struct Hints: Equatable {
        var amount: Decimal?
        var currency: String?
        var dueDate: Date?
        var accountNumber: String?

        var isEmpty: Bool {
            amount == nil && currency == nil && dueDate == nil && accountNumber == nil
        }
    }

    func parse(_ text: String) -> Hints {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Hints()
        }
        let money = bestAmount(in: text)
        return Hints(
            amount: money?.value,
            currency: money?.currency,
            dueDate: dueDate(in: text),
            accountNumber: accountNumber(in: text)
        )
    }

    // MARK: - Amount + currency

    private struct Money { let value: Decimal; let currency: String }

    // Prefer an amount that sits near a "due / total / balance / pay" keyword;
    // otherwise fall back to the largest currency-marked number in the text.
    private func bestAmount(in text: String) -> Money? {
        let all = moneyMatches(in: text)
        guard !all.isEmpty else { return nil }

        let keywords = ["amount due", "total due", "balance due", "pay this amount",
                        "amount enclosed", "total amount", "balance", "total", "amount", "due"]
        let lower = text.lowercased() as NSString
        for kw in keywords {
            var searchFrom = 0
            while searchFrom < lower.length {
                let kwRange = lower.range(of: kw, range: NSRange(location: searchFrom, length: lower.length - searchFrom))
                guard kwRange.location != NSNotFound else { break }
                // The first money match that starts within ~40 chars after the keyword.
                let windowEnd = min(lower.length, kwRange.location + kw.count + 40)
                if let hit = all.first(where: {
                    $0.range.location >= kwRange.location && $0.range.location <= windowEnd
                }) {
                    return Money(value: hit.value, currency: hit.currency)
                }
                searchFrom = kwRange.location + kwRange.length
            }
        }

        // No keyword nearby: take the largest amount that ACTUALLY has a currency
        // marker ($ / € / £ / USD…). We do NOT fall back to bare decimals here:
        // form/reference codes like "PC0313.00" look like money to a regex but
        // aren't. A bare decimal only counts when it sits next to an amount/total/
        // due keyword (handled in the loop above).
        if let best = all.filter(\.hasCurrency).max(by: { $0.value < $1.value }) {
            return Money(value: best.value, currency: best.currency)
        }
        return nil
    }

    private struct MoneyMatch { let value: Decimal; let currency: String; let hasCurrency: Bool; let range: NSRange }

    // Find every money-looking token: an optional symbol/code, then a number
    // with optional thousands separators and cents.
    private func moneyMatches(in text: String) -> [MoneyMatch] {
        // e.g. "$1,234.56"  "USD 86.42"  "€ 90"  "1,200.00 USD"
        let pattern = #"(?:(\$|€|£)|\b(USD|EUR|GBP)\b)\s?(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)|(\d{1,3}(?:,\d{3})*\.\d{2})\s?(USD|EUR|GBP)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))

        return matches.compactMap { m in
            // Number is in group 3 (symbol/code-led) or group 4 (trailing-code).
            let numRange = m.range(at: 3).location != NSNotFound ? m.range(at: 3) : m.range(at: 4)
            guard numRange.location != NSNotFound else { return nil }
            let raw = ns.substring(with: numRange).replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(string: raw) else { return nil }

            let symbol = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            let code = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2))
                     : (m.range(at: 5).location != NSNotFound ? ns.substring(with: m.range(at: 5)) : "")
            let hasCurrency = !symbol.isEmpty || !code.isEmpty
            return MoneyMatch(value: value, currency: currencyCode(symbol: symbol, code: code),
                              hasCurrency: hasCurrency, range: m.range)
        }
    }

    private func currencyCode(symbol: String, code: String) -> String {
        if !code.isEmpty { return code.uppercased() }
        switch symbol {
        case "€": return "EUR"
        case "£": return "GBP"
        default:  return "USD"   // "$" → USD (Phase 1 is US-first)
        }
    }

    // MARK: - Due date
    //
    // We scan for explicit date tokens with our own regexes instead of
    // NSDataDetector: the detector swallows trigger words ("due on 06/15/2026")
    // into the match and then mis-resolves it to today's date. Handling the
    // formats ourselves keeps it deterministic. Covered: MM/DD/YYYY (US),
    // ISO yyyy-MM-dd, and "Month DD, YYYY". (Day-first "15 June 2026" is not
    // handled — Phase 1 is US-first.)

    private func dueDate(in text: String) -> Date? {
        let candidates = dateCandidates(in: text)
        guard !candidates.isEmpty else { return nil }
        let ns = text as NSString

        // Prefer a date whose preceding ~30 chars mention "due" / "pay by" /
        // "deadline" — that's the date that matters on a bill. Judged per
        // candidate so an unrelated first date isn't picked by accident.
        // Context words that mark a date as the actionable one. Beyond bills:
        // real Plaino docs are appointments, prescriptions, travel, deadlines —
        // so "expires", "appointment", "departure" etc. count too (learned from
        // the real Week-4 samples: a Costco Rx expiry, a GEICO appointment, a
        // flight departure are all "the date that matters").
        let cues = ["due", "pay by", "deadline", "by ", "expires", "expire",
                    "appointment", "departure", "depart", "valid until", "renew", "no later"]
        for c in candidates {
            let start = max(0, c.loc - 30)
            let prefix = ns.substring(with: NSRange(location: start, length: c.loc - start)).lowercased()
            if cues.contains(where: prefix.contains) {
                return c.date
            }
        }
        // No cue. If there's exactly ONE date in the whole document it's an
        // unambiguous guess (e.g. a single appointment date). If there are
        // several with no cue, DON'T guess — return nil and let the LLM pick
        // the right one (it reads context better than "first date wins", which
        // wrongly grabbed an email's sent-date on the flight sample).
        return candidates.count == 1 ? candidates.first?.date : nil
    }

    private struct DateHit { let date: Date; let loc: Int }

    private func dateCandidates(in text: String) -> [DateHit] {
        var hits: [DateHit] = []
        let ns = text as NSString

        func scan(_ pattern: String, _ make: (NSTextCheckingResult, NSString) -> Date?) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let d = make(m, ns) { hits.append(DateHit(date: d, loc: m.range.location)) }
            }
        }
        func intAt(_ m: NSTextCheckingResult, _ i: Int, _ ns: NSString) -> Int? {
            guard m.range(at: i).location != NSNotFound else { return nil }
            return Int(ns.substring(with: m.range(at: i)))
        }

        // MM/DD/YYYY or M/D/YY (US order)
        scan(#"\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b"#) { m, ns in
            guard let mo = intAt(m, 1, ns), let dy = intAt(m, 2, ns), var yr = intAt(m, 3, ns) else { return nil }
            if yr < 100 { yr += 2000 }
            return Self.makeDate(year: yr, month: mo, day: dy)
        }
        // ISO yyyy-MM-dd
        scan(#"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#) { m, ns in
            guard let yr = intAt(m, 1, ns), let mo = intAt(m, 2, ns), let dy = intAt(m, 3, ns) else { return nil }
            return Self.makeDate(year: yr, month: mo, day: dy)
        }
        // "Month DD, YYYY" / "Mon DD YYYY" / "June 15th 2026"
        scan(#"\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b"#) { m, ns in
            guard let mo = Self.monthNumber(ns.substring(with: m.range(at: 1))),
                  let dy = intAt(m, 2, ns), let yr = intAt(m, 3, ns) else { return nil }
            return Self.makeDate(year: yr, month: mo, day: dy)
        }

        return hits.sorted { $0.loc < $1.loc }
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), year > 1900 else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func monthNumber(_ s: String) -> Int? {
        let names = ["january", "february", "march", "april", "may", "june",
                     "july", "august", "september", "october", "november", "december"]
        let low = s.lowercased()
        for (i, name) in names.enumerated() where low == name || name.hasPrefix(low) && low.count >= 3 {
            return i + 1
        }
        return nil
    }

    // MARK: - Account / reference number

    private func accountNumber(in text: String) -> String? {
        // The leading word names the kind of number; the middle word (number /
        // no. / # / id) is an optional qualifier. Real samples use "Customer ID",
        // "Member No.", "Invoice No." — not just "Account number".
        let pattern = #"(?:account|acct|a/c|reference|ref|member|customer|policy|invoice|violation|claim)\s*(?:number|no\.?|#|num|id)?\s*[:#]?\s*([0-9][0-9\- ]{3,}[0-9])"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.range(at: 1).location != NSNotFound else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        // Normalize: drop spaces, keep digits and dashes.
        return raw.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces)
    }
}
