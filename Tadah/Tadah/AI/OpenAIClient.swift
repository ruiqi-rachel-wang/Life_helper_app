//  OpenAIClient.swift
//
//  The real Extractor: sends the OCR text to the model and gets back a
//  structured ExtractionResult. Uses gpt-4o (not 4o-mini) because users need
//  real REASONING — explain *why* they got this, find the root cause, and give
//  conditional next steps — not just field extraction. ~$0.003–0.006/scan;
//  affordable because scans+guides are rate-limited (see ScanQuota: 10/day, 20 per 30 days).
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
    var model: String = "gpt-4o"            // extraction — needs reasoning
    var polishModel: String = "gpt-4o-mini" // guide polish — only light rewording, keep it cheap
    // The Worker when configured (no key on the phone), else OpenAI direct (dev).
    var endpoint = BackendConfig.chatEndpoint
    var usesWorker = BackendConfig.usesWorker
    var session: URLSession = .shared

    // Build an authorized POST. When going through the Worker we send NO key —
    // the Worker holds it; for the direct dev path we add the Bearer header.
    private func request(body: Data) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if usesWorker {
            // No OpenAI key on the phone; send the optional shared-secret if configured.
            if !BackendConfig.proxyToken.isEmpty {
                req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
            }
            // Anonymous install id (same one metrics use) — lets the Worker enforce
            // its per-install AI quota, the server-side backstop to ScanQuota.
            req.setValue(Install.id, forHTTPHeaderField: "X-Cuevi-Install")
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    // We can call the model if the Worker is configured (it holds the key) OR a
    // real dev key is present for the direct path.
    private var canCall: Bool {
        usesWorker || (apiKey.hasPrefix("sk-") && !apiKey.contains("REPLACE"))
    }

    enum ClientError: LocalizedError {
        case missingKey
        case http(Int, String)
        case emptyContent
        case badJSON

        var errorDescription: String? {
            switch self {
            case .missingKey:        return "No OpenAI key set. Add it in APIKeys.swift."
            // 429 = the Worker's rate/quota guard (or OpenAI itself) said "not now" —
            // tell the user something they can act on, not an HTTP code.
            case .http(429, _):      return String(localized: "The AI service is busy or this device hit its limit — please try again later.")
            case .http(let c, _):    return "OpenAI request failed (HTTP \(c))."
            case .emptyContent:      return "OpenAI returned no content."
            case .badJSON:           return "Couldn't parse the AI response."
            }
        }
    }

    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult] {
        // Need either the Worker (holds the key) or a real dev key for the direct path.
        guard canCall else { throw ClientError.missingKey }

        let body = ChatRequest(
            model: model,
            response_format: .init(type: "json_object"),
            temperature: 0.2,
            max_tokens: 2000,
            messages: [
                .init(role: "system", content: ScanPrompt.systemPrompt(language: language)),
                .init(role: "user", content: ScanPrompt.userPrompt(text: text, hints: hints)),
            ]
        )

        let req = request(body: try JSONEncoder().encode(body))
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
}

// MARK: - Wire types (Codable bridges to/from JSON)

private nonisolated struct ChatRequest: Encodable {
    struct ResponseFormat: Encodable { let type: String }
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let response_format: ResponseFormat
    let temperature: Double
    let max_tokens: Int
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
            accountLabel: str("accountLabel"),
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

        // FIRST: a time WITH a UTC offset (e.g. "2026-06-25T08:05-04:00"). A flight
        // departs at 8:05 in NEW YORK's time, not the phone's — the offset pins the
        // correct absolute instant so the reminder fires right even on a Chicago
        // phone. The format carries its own zone, so we don't set f.timeZone.
        for fmt in ["yyyy-MM-dd'T'HH:mmZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return (d, true) }
        }

        // Otherwise a local time with no offset — interpret in the device timezone.
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
        case "car", "vehicle", "automobile", "auto insurance", "registration":
            return .auto
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

// MARK: - Guide build (Week 7–8) — ONE AI call per guide

// One utility company that serves a ZIP, with whatever contact methods it offers.
// The lookup's goal is the NAME; a website/phone/in-person is filled only when the
// model is confident — we'd rather show just a name than a wrong number.
nonisolated struct LocalUtility {
    var kind: String        // "Electricity", "Gas", "Water & sewer", "Trash & recycling", "Internet"
    var name: String
    var website: String?    // bare domain, e.g. "austinenergy.com"
    var phone: String?      // e.g. "512-494-9400"
    var inPerson: String?   // office / where-to-go, if known
}

extension OpenAIClient {
    // Build a guide in a SINGLE AI call: reword the deterministic checklist to read
    // naturally and — only when a valid ZIP is given — also look up the local
    // utility companies, both in one JSON response. Best-effort: returns the base
    // steps UNCHANGED and no providers on any failure (no key, offline, bad JSON),
    // so a guide never blocks on the model. Uses the cheap polish model.
    // The caller merges `providers` into its utilities step (see GuidesView).
    func buildGuide(_ base: ExtractionResult,
                    context: String,
                    zip: String? = nil,
                    language: ExplainLanguage = .english) async -> (result: ExtractionResult, providers: [LocalUtility]) {
        guard canCall, !base.steps.isEmpty else { return (base, []) }

        // Only ask for utilities when the ZIP is a real 5-digit US ZIP (the ZIP
        // question only appears on housing guides, so this is the only time we ask).
        let z = zip?.trimmingCharacters(in: .whitespaces)
        let wantsUtilities = z.map { $0.count == 5 && $0.allSatisfy(\.isNumber) } ?? false

        // Naming real local companies needs real reasoning (which county is this ZIP
        // actually in, does that company really serve it) — the cheap polish model
        // was confidently naming the WRONG company for the area. Only pay for the
        // stronger model on the (less common) ZIP-lookup path; plain rewording stays cheap.
        let body = ChatRequest(
            model: wantsUtilities ? model : polishModel, response_format: .init(type: "json_object"), temperature: 0.2, max_tokens: 1200,
            messages: [
                .init(role: "system", content: GuidePrompt.system(includeUtilities: wantsUtilities, language: language)),
                .init(role: "user", content: GuidePrompt.user(context: context, steps: base.steps, zip: wantsUtilities ? z : nil)),
            ])

        guard let httpBody = try? JSONEncoder().encode(body) else { return (base, []) }
        let req = request(body: httpBody)
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let chat = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = chat.choices.first?.message.content,
              let json = content.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        else { return (base, []) }

        // The model sometimes returns steps as objects ({"action":…}/{"step":…})
        // instead of plain strings — coerce both so the rewrite isn't lost.
        func stepStrings() -> [String] {
            guard let arr = dict["steps"] as? [Any] else { return [] }
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
        let steps = stepStrings().map(ExtractionJSON.stripLeadingNumber)
        // Only accept the rewrite if the COUNT is unchanged — otherwise the
        // milestone↔detail alignment breaks and an authored (safety) step could
        // silently vanish. On any mismatch keep the deterministic steps.
        // Notes are left exactly as authored — the rewrite never adds its own.
        if steps.count == base.steps.count, !steps.contains(where: { $0.isEmpty }) {
            out.steps = steps
        }

        let providers = wantsUtilities ? Self.parseProviders(dict["providers"]) : []
        return (out, providers)
    }

    // Coerce the model's "providers" array into [LocalUtility], dropping entries
    // without a name and any field the model left null/empty.
    private static func parseProviders(_ raw: Any?) -> [LocalUtility] {
        guard let arr = raw as? [Any] else { return [] }
        func clean(_ v: Any?) -> String? {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty, s.lowercased() != "null" else { return nil }
            return s
        }
        return arr.compactMap { el -> LocalUtility? in
            guard let o = el as? [String: Any],
                  let kind = clean(o["kind"]), let name = clean(o["name"]) else { return nil }
            // Drop the scheme if the model included one — linkified adds https://.
            let website = clean(o["website"]).map {
                $0.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            }
            return LocalUtility(kind: kind, name: name, website: website,
                                phone: clean(o["phone"]), inPerson: clean(o["inPerson"]))
        }
    }
}
