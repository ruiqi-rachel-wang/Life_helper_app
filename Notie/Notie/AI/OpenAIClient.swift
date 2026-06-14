//  OpenAIClient.swift
//
//  The real Extractor: sends the OCR text to GPT-4o-mini and gets back a
//  structured ExtractionResult. Cheap (~$0.0004/scan) because the task is
//  plain extraction from clean text, not reasoning.
//
//  WEEK 5: calls api.openai.com DIRECTLY with the dev key in APIKeys.swift.
//  Safe because this only runs on the Simulator. Before TestFlight the URL +
//  auth header swap to a Cloudflare Worker so the key never ships — and
//  because this type is just an `Extractor`, nothing else has to change.
//
//  Uses JSON mode (response_format = json_object) so the model must return
//  parseable JSON. We ask for stable string values (amount as "86.42",
//  dueDate as "YYYY-MM-DD") to avoid float/format ambiguity, then convert.
//

import Foundation

nonisolated struct OpenAIClient: Extractor {
    var apiKey: String = APIKeys.openAI
    var model: String = "gpt-4o-mini"
    var endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    var session: URLSession = .shared

    enum ClientError: LocalizedError {
        case missingKey
        case http(Int, String)
        case emptyContent
        case badJSON

        var errorDescription: String? {
            switch self {
            case .missingKey:        return "No OpenAI key set. Add it in APIKeys.swift."
            case .http(let c, _):    return "OpenAI request failed (HTTP \(c))."
            case .emptyContent:      return "OpenAI returned no content."
            case .badJSON:           return "Couldn't parse the AI response."
            }
        }
    }

    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult] {
        // Validate THIS client's key (injected or default), not a global — so an
        // injected client / the future Worker swap behaves as the protocol implies.
        guard apiKey.hasPrefix("sk-"), !apiKey.contains("REPLACE") else {
            throw ClientError.missingKey
        }

        let body = ChatRequest(
            model: model,
            response_format: .init(type: "json_object"),
            temperature: 0.2,
            messages: [
                .init(role: "system", content: Self.systemPrompt(language: language)),
                .init(role: "user", content: Self.userPrompt(text: text, hints: hints)),
            ]
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.http(0, "") }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content, !content.isEmpty else {
            throw ClientError.emptyContent
        }
        let results = ExtractionJSON.parseItems(content)
        guard !results.isEmpty else { throw ClientError.badJSON }
        return results
    }

    // MARK: - Prompts
    // Tuned against the 5 real Week-4 OCR samples. Keep the JSON contract here
    // and the DTO below in sync.

    static func systemPrompt(language: ExplainLanguage) -> String {
        """
        You read a single piece of mail, a bill, an email, or a screenshot that \
        has been OCR'd (so it may have typos and broken lines) and explain it in \
        plain words to someone who may not read English well and may have no idea \
        what the document is.

        Return ONLY a JSON object of the form {"items": [ ... ]}. MOST documents
        have exactly ONE item. Include SEVERAL items only when the document clearly
        lists separate things — e.g. multiple appointments, multiple bills, or two
        different deadlines — one object per thing; do not split a single task.
        Each item in "items" has these keys (use null when unknown):
          title         : a SHORT headline for a list row (≤ ~5 words), e.g.
                          "Con Edison electricity bill", "Flight to Chicago",
                          "Neurology appointment"
          documentType  : short label, e.g. "Utility bill", "Parking ticket"
          sender        : the organization that sent it, e.g. "Con Edison"
          senderShort   : a 1-2 word short form for a chip
          amount        : the amount owed as a STRING like "86.42" (no symbol), or null
                          (null if nothing is owed, e.g. a paid receipt or a credit).
                          For a credit-card or loan statement, use the FULL statement /
                          new balance (paying that avoids interest) — NOT the minimum
                          payment. Ignore form/reference codes (e.g. "PC0313.00",
                          policy/claim numbers) — those are NOT amounts.
          currency      : ISO 4217 like "USD", or null
          dueDate       : the SINGLE most important action date, or null. Use "YYYY-MM-DD"
                          for a plain deadline; use "YYYY-MM-DDTHH:MM" (24-hour) when the
                          event has a SPECIFIC TIME, like a flight departure or an
                          appointment (e.g. "2026-06-25T08:05"). Not every doc is a bill —
                          it may be a payment due date, appointment, flight departure,
                          prescription/registration expiry, or submission deadline. The date
                          an email was SENT is NOT the due date. If the deadline is in words
                          (e.g. "within 90 days of the exam"), compute it and add "dueDate"
                          to lowConfidenceFields.
          accountNumber : the PRIMARY account / reference / confirmation / violation number, or null
          otherIDs      : ALL other identifiers the reader may need later, as an array of
                          {"label","value"} objects (claim #, policy #, eTicket, member #,
                          customer ID, …). Always capture claim and policy numbers. [] if none.
          category      : EXACTLY one of these 8 lowercase words and NOTHING else:
                          utility, government, medical, finance, housing, work, personal, other.
                          Travel, flights, appointments, and personal errands are "personal".
                          Never invent a category like "travel" — use one of the 8.
          summary       : in \(language.promptName). Say WHAT KIND of document this is and
                          what it's about. Keep it AS SHORT AS POSSIBLE: for a self-
                          explanatory document, ONE plain sentence with the key facts is
                          enough — e.g. "This is a flight ticket from New York to Chicago,
                          flight UA623, departing June 25 at 8:05 AM." Only add more
                          explanation when there's a term or situation the reader likely
                          won't understand (e.g. the insurance "storage facility" = the tow
                          yard / body shop where their car is kept after the accident). Add
                          understanding, do NOT just reword the text, and don't pad it.
          steps         : the concrete, ORDERED actions to get this done, in
                          \(language.promptName). Be specific and operational, not vague — no
                          "pay it" / "contact them". When there is an ONLINE option, give it
                          as a step WITH the website/app (e.g. "Check in online at united.com,
                          or check in at the airport counter"), then real next steps (e.g.
                          "arrive ~2 hours early", "go through security", "find your gate").
                          For a bill: "Go to <site> and log in", "open the bill", "pay and
                          save the confirmation". If a step is a phone call or visit AND
                          \(language.promptName) is not English, add a sub-step to ask for an
                          interpreter in \(language.promptName). Use [] if nothing to do.
          notes         : short helpful side-info that is NOT an action — who to contact and
                          how, useful context, caveats, deadlines context. Phone numbers and
                          URLs welcome here. [] if none.
          siteURL       : a relevant URL if the document names one, else null
          repeats       : one of "monthly", "yearly", "every:N" (N = days), or null for one-off — only if the document recurs
          confidence    : your overall confidence 0.0-1.0
          lowConfidenceFields : array of field names you are unsure about

        If the document shows interest charged, a late fee, or any penalty, treat it \
        as a likely missed or late payment: in notes, (a) gently note they may have \
        missed a payment, (b) suggest paying the full balance and setting a reminder \
        so it doesn't happen again, and (c) tell them they can call the company (use \
        any phone number shown) to ask for a one-time waiver or refund of the fee. \
        For a statement with a minimum payment, add a note that paying only the \
        minimum (and the minimum amount) accrues interest at the stated APR.

        For a flight or travel document, steps should include checking in (online \
        AND at the airport counter), arriving ~2 hours early, going through security, \
        and finding the gate; put the flight number in otherIDs; and add a note on \
        how to check the live gate/status (the airline's website, or searching the \
        flight number). Set siteURL to the airline's site when known.

        If the text is unreadable or meaningless (gibberish, too garbled to tell \
        what it is), return ONE item with documentType "unknown", a short summary \
        saying you couldn't read it, steps [], and confidence below 0.2. Never \
        invent a document.

        Write summary and steps in \(language.promptName). Do not invent an amount \
        or a date that is not in the text.
        """
    }

    static func userPrompt(text: String, hints: RuleBasedParser.Hints) -> String {
        var known = ""
        if let a = hints.amount { known += "\n- amount candidate (exact digits from regex): \(a) — use this number for the amount IF money is actually owed; if this is a credit, a paid receipt, or a positive balance, set amount to null" }
        if let c = hints.currency { known += "\n- currency (regex-detected): \(c)" }
        if let d = hints.dueDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            known += "\n- dueDate (regex-detected, trust this): \(f.string(from: d))"
        }
        if let n = hints.accountNumber { known += "\n- accountNumber (regex-detected): \(n)" }

        let knownBlock = known.isEmpty ? "" : "\n\nFields already detected by exact rules (prefer these):\(known)"
        return "OCR TEXT:\n\"\"\"\n\(text)\n\"\"\"\(knownBlock)"
    }
}

// MARK: - Wire types (Codable bridges to/from JSON)

private nonisolated struct ChatRequest: Encodable {
    struct ResponseFormat: Encodable { let type: String }
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let response_format: ResponseFormat
    let temperature: Double
    let messages: [Message]
}

private nonisolated struct ChatResponse: Decodable {
    struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
    let choices: [Choice]
}

// Parses the model's JSON into ExtractionResult. We use JSONSerialization +
// per-field coercion rather than a strict Codable DTO ON PURPOSE: LLM JSON is
// loose — it returned `"confidence": "high"` (a string) and may return a number
// where we asked for a string, etc. Strict decoding would throw away the WHOLE
// result over one odd field. Here each field is coerced independently, so a
// surprise in one field never loses the others. (Made into a type so it's
// testable without a network call — see OpenAIClientParsingTests.)
nonisolated enum ExtractionJSON {
    // A document usually yields ONE item, but may yield several (a list of
    // appointments, two deadlines…). The model returns {"items":[ ... ]}; we also
    // accept a bare single object for robustness.
    static func parse(_ content: String) -> ExtractionResult? {
        guard let dict = object(content) else { return nil }
        if let items = dict["items"] as? [Any], let first = items.first as? [String: Any] {
            return item(from: first)
        }
        return item(from: dict)
    }

    static func parseItems(_ content: String) -> [ExtractionResult] {
        guard let dict = object(content) else { return [] }
        if let items = dict["items"] as? [Any] {
            return items.compactMap { ($0 as? [String: Any]).map(item(from:)) }
        }
        return [item(from: dict)]
    }

    private static func object(_ content: String) -> [String: Any]? {
        guard let data = content.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func item(from dict: [String: Any]) -> ExtractionResult {

        func str(_ key: String) -> String? {
            guard let v = dict[key], !(v is NSNull) else { return nil }
            let s = (v as? String) ?? String(describing: v)
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.isEmpty || t.lowercased() == "null") ? nil : t
        }
        func decimal(_ key: String) -> Decimal? {
            guard let v = dict[key], !(v is NSNull) else { return nil }
            if let n = v as? NSNumber { return Decimal(string: n.stringValue) }
            if let s = v as? String { return Decimal(string: s.replacingOccurrences(of: ",", with: "")) }
            return nil
        }
        func confidence() -> Double {
            guard let v = dict["confidence"], !(v is NSNull) else { return 0 }
            if let n = v as? NSNumber { return n.doubleValue }
            if let s = v as? String {
                if let d = Double(s) { return d }
                switch s.lowercased() {
                case "very high", "high": return 0.9
                case "medium", "moderate": return 0.6
                case "low": return 0.3
                default: return 0.5
                }
            }
            return 0
        }
        func stringList(_ key: String) -> [String] {
            (dict[key] as? [Any])?
                .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
        }
        let steps = stringList("steps").map(stripLeadingNumber)
        let notes = stringList("notes")
        let due = parseDueDate(str("dueDate"))
        let lowConf = (dict["lowConfidenceFields"] as? [Any])?.compactMap { $0 as? String } ?? []
        // The model sometimes returns category as ["finance"] instead of "finance".
        let categoryRaw = (dict["category"] as? String)
            ?? (dict["category"] as? [Any])?.compactMap { $0 as? String }.first
        let otherIDs = (dict["otherIDs"] as? [Any])?.compactMap { item -> DocID? in
            guard let o = item as? [String: Any],
                  let value = (o["value"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !value.isEmpty else { return nil }
            let label = (o["label"] as? String)?.trimmingCharacters(in: .whitespaces)
            return DocID(label: (label?.isEmpty == false ? label! : "ID"), value: value)
        } ?? []

        return ExtractionResult(
            title: str("title"),
            documentType: str("documentType"),
            sender: str("sender"),
            senderShort: str("senderShort"),
            amount: decimal("amount"),
            currency: str("currency"),
            dueDate: due.date,
            dueHasTime: due.hasTime,
            accountNumber: str("accountNumber"),
            otherIDs: otherIDs,
            category: normalizedCategory(categoryRaw),
            summary: str("summary"),
            steps: steps,
            notes: notes,
            siteURL: str("siteURL").flatMap { URL(string: $0) },
            repeats: parseRepeats(str("repeats")),
            confidence: confidence(),
            lowConfidenceFields: Set(lowConf)
        )
    }

    // Drop a leading "1." / "2)" the model sometimes adds — steps shouldn't be
    // numbered (the UI handles ordering, and other items aren't numbered).
    static func stripLeadingNumber(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            return String(t[r.upperBound...])
        }
        return t
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.date(from: s)
    }

    // The model returns "YYYY-MM-DD" for a plain deadline, or "YYYY-MM-DDTHH:MM"
    // when the event has a specific time (a flight departure, an appointment).
    // hasTime lets the UI show the time and Week 6 schedule a reminder N hours
    // before it (not just at 9am the day-of).
    static func parseDueDate(_ s: String?) -> (date: Date?, hasTime: Bool) {
        guard let s, !s.isEmpty else { return (nil, false) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                // Midnight means the model appended a placeholder time to a
                // plain date (a bill, not a 12:00 AM event) — treat as no time.
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                return (d, !(c.hour == 0 && c.minute == 0))
            }
        }
        return (parseDate(s), false)
    }

    // Map the model's category to one of our 8 enum cases. The model sometimes
    // returns a sensible-but-off word ("insurance", "travel") despite the prompt;
    // this catches the common ones so we don't lose the category. Truly unknown
    // → nil (the user/Review can set it).
    static func normalizedCategory(_ raw: String?) -> ItemCategory? {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let exact = ItemCategory(rawValue: raw) { return exact }
        switch raw {
        case "travel", "flight", "flights", "appointment", "appointments", "errand", "errands":
            return .personal
        case "insurance", "bank", "banking", "loan", "investment", "credit card":
            return .finance
        case "tax", "taxes", "dmv", "immigration", "court", "license", "ticket", "violation":
            return .government
        case "rent", "mortgage", "lease", "apartment":
            return .housing
        case "health", "dental", "pharmacy", "prescription", "clinic", "hospital":
            return .medical
        case "electricity", "water", "internet", "cable":
            return .utility
        case "job", "employer", "employment", "payroll":
            return .work
        default:
            return nil
        }
    }

    static func parseRepeats(_ s: String?) -> Recurrence? {
        guard let s = s?.lowercased(), s != "null", !s.isEmpty else { return nil }
        if s == "monthly" { return .monthly }
        if s == "yearly" || s == "annually" { return .yearly }
        if s.hasPrefix("every") {
            let digits = s.filter(\.isNumber)
            if let n = Int(digits), n > 0 { return .everyNDays(n) }
        }
        return nil
    }
}

// MARK: - Guide polish (Week 7)

extension OpenAIClient {
    // Best-effort: reword a deterministic guide checklist to read naturally for
    // this person and add a tip or two. Returns the base UNCHANGED on any
    // failure (no key, offline, bad JSON) — guides must never block on the model.
    func polish(_ base: ExtractionResult,
                context: String,
                language: ExplainLanguage = .english) async -> ExtractionResult {
        guard apiKey.hasPrefix("sk-"), !apiKey.contains("REPLACE"), !base.steps.isEmpty else { return base }

        let system = """
        You LIGHTLY polish a checklist for someone who may not read English well. \
        Make MINIMAL changes: keep each step's meaning, order, and any URLs; only \
        fix wording for clarity. Do NOT add, remove, reorder, or merge steps. You \
        may add 1-2 short tips in "notes". Reply ONLY as JSON \
        {"steps":[...],"notes":[...]} in \(language.promptName).
        """
        let user = "Situation: \(context)\nSteps:\n"
            + base.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body = ChatRequest(
            model: model, response_format: .init(type: "json_object"), temperature: 0.2,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)])

        guard let httpBody = try? JSONEncoder().encode(body) else { return base }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = httpBody

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = chat.choices.first?.message.content,
              let json = content.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        else { return base }

        // The model sometimes returns steps as objects ({"action":…}/{"step":…})
        // instead of plain strings — coerce both so the polish isn't lost.
        func list(_ key: String) -> [String] {
            guard let arr = dict[key] as? [Any] else { return [] }
            return arr.compactMap { el -> String? in
                if let s = el as? String { return s.trimmingCharacters(in: .whitespaces) }
                if let o = el as? [String: Any] {
                    let v = (o["action"] ?? o["text"] ?? o["step"] ?? o["note"]) as? String
                    return v?.trimmingCharacters(in: .whitespaces)
                }
                return nil
            }.filter { !$0.isEmpty }
        }
        var out = base
        let steps = list("steps").map(ExtractionJSON.stripLeadingNumber), notes = list("notes")
        if !steps.isEmpty { out.steps = steps }
        if !notes.isEmpty { out.notes = notes }
        return out
    }
}
