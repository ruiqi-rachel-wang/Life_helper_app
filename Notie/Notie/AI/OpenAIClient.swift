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

struct OpenAIClient: Extractor {
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
                 language: ExplainLanguage) async throws -> ExtractionResult {
        guard APIKeys.hasOpenAIKey else { throw ClientError.missingKey }

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
        guard let result = ExtractionJSON.parse(content) else { throw ClientError.badJSON }
        return result
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

        Return ONLY a JSON object with these keys (use null when unknown):
          documentType  : short label, e.g. "Utility bill", "Parking ticket"
          sender        : the organization that sent it, e.g. "Con Edison"
          senderShort   : a 1-2 word short form for a chip
          amount        : the amount owed as a STRING like "86.42" (no symbol), or null
                          (null if nothing is owed, e.g. a paid receipt or a credit)
          currency      : ISO 4217 like "USD", or null
          dueDate       : the SINGLE most important action date as "YYYY-MM-DD", or null.
                          Not every doc is a bill — this may be a payment due date, an
                          appointment date, a flight departure, a prescription/registration
                          expiry, or a submission deadline. The date an email was SENT is
                          NOT the due date. If the deadline is described in words (e.g.
                          "within 90 days of the exam"), compute it and add "dueDate" to
                          lowConfidenceFields.
          accountNumber : the PRIMARY account / reference / confirmation / violation number, or null
          otherIDs      : any OTHER identifiers as an array of {"label","value"} objects
                          (eTicket, member #, customer ID, policy #, …), or [] if none
          category      : EXACTLY one of these 8 lowercase words and NOTHING else:
                          utility, government, medical, finance, housing, work, personal, other.
                          Travel, flights, appointments, and personal errands are "personal".
                          Never invent a category like "travel" — use one of the 8.
          summary       : a few short sentences in \(language.promptName) explaining what this is and what to do
          steps         : action steps in \(language.promptName), each a plain imperative; a step
                          may include a URL; use [] if there is nothing to do
          siteURL       : a relevant URL if the document names one, else null
          repeats       : one of "monthly", "yearly", "every:N" (N = days), or null for one-off — only if the document recurs
          confidence    : your overall confidence 0.0-1.0
          lowConfidenceFields : array of field names you are unsure about

        Write summary and steps in \(language.promptName). Do not invent an amount \
        or a date that is not in the text.
        """
    }

    static func userPrompt(text: String, hints: RuleBasedParser.Hints) -> String {
        var known = ""
        if let a = hints.amount { known += "\n- amount (regex-detected, trust this): \(a)" }
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

private struct ChatRequest: Encodable {
    struct ResponseFormat: Encodable { let type: String }
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let response_format: ResponseFormat
    let temperature: Double
    let messages: [Message]
}

private struct ChatResponse: Decodable {
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
enum ExtractionJSON {
    static func parse(_ content: String) -> ExtractionResult? {
        guard let data = content.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

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
        let steps = (dict["steps"] as? [Any])?
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
        let lowConf = (dict["lowConfidenceFields"] as? [Any])?.compactMap { $0 as? String } ?? []
        let otherIDs = (dict["otherIDs"] as? [Any])?.compactMap { item -> DocID? in
            guard let o = item as? [String: Any],
                  let value = (o["value"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !value.isEmpty else { return nil }
            let label = (o["label"] as? String)?.trimmingCharacters(in: .whitespaces)
            return DocID(label: (label?.isEmpty == false ? label! : "ID"), value: value)
        } ?? []

        return ExtractionResult(
            documentType: str("documentType"),
            sender: str("sender"),
            senderShort: str("senderShort"),
            amount: decimal("amount"),
            currency: str("currency"),
            dueDate: parseDate(str("dueDate")),
            accountNumber: str("accountNumber"),
            otherIDs: otherIDs,
            category: str("category").flatMap { ItemCategory(rawValue: $0.lowercased()) },
            summary: str("summary"),
            steps: steps,
            siteURL: str("siteURL").flatMap { URL(string: $0) },
            repeats: parseRepeats(str("repeats")),
            confidence: confidence(),
            lowConfidenceFields: Set(lowConf)
        )
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f.date(from: s)
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
