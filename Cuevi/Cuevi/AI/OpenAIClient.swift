//  OpenAIClient.swift
//
//  The real Extractor: sends the OCR text to the model and gets back a
//  structured ExtractionResult. Uses gpt-4o (not 4o-mini) because users need
//  real REASONING — explain *why* they got this, find the root cause, and give
//  conditional next steps — not just field extraction. ~$0.003–0.006/scan;
//  affordable because scans are rate-limited (see ScanQuota: 10/day, 50/month).
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
                .init(role: "system", content: Self.systemPrompt(language: language)),
                .init(role: "user", content: Self.userPrompt(text: text, hints: hints)),
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

    // MARK: - Prompts
    // Tuned against the 5 real Week-4 OCR samples. Keep the JSON contract here
    // and the DTO below in sync.

    static func systemPrompt(language: ExplainLanguage) -> String {
        """
        You read a single piece of mail, a bill, an email, or a screenshot that \
        has been OCR'd (so it may have typos and broken lines) and explain it in \
        plain words to someone who may not read English well and may have no idea \
        what the document is. It could be ANYTHING — a bill, a ticket, a government \
        or court letter, a medical or insurance notice, an appointment, a flight, a \
        receipt, a school/immigration form, a subscription, a legal notice, etc.

        The specific examples in these instructions (a parking ticket, a flight, an \
        electricity bill) are ILLUSTRATIONS of the principles, NOT templates. First \
        work out what THIS document actually is, then apply the principles to it. \
        Never force an example's framing onto an unrelated document.

        Return ONLY a JSON object of the form {"items": [ ... ]}. MOST documents
        have exactly ONE item. Include SEVERAL items only when the document clearly
        lists separate things — e.g. multiple appointments, multiple bills, or two
        different deadlines — one object per thing; do not split a single task.
        Each item in "items" has these keys (use null when unknown):
          title         : a SHORT headline for a list row (≤ ~5 words), written in
                          \(language.promptName) (the English examples here are only
                          illustrations): "Con Edison electricity bill", "Flight to Chicago",
                          "Neurology appointment". Translate the title like the summary —
                          never leave it in the document's original language.
          documentType  : short label IN \(language.promptName) (English examples here only):
                          "Utility bill", "Parking ticket". (sender stays the org's real name.)
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
                          for a plain deadline. When the event has a SPECIFIC TIME (a flight
                          departure, an appointment), use "YYYY-MM-DDTHH:MM" (24-hour). If
                          that time happens at a PHYSICAL PLACE in a known timezone (a flight
                          leaving New York, an in-person appointment in a city), APPEND that
                          place's UTC offset so the reminder is correct even if the phone is
                          in another timezone — e.g. an 8:05 AM departure from New York in
                          June is "2026-06-25T08:05-04:00" (EDT). Keep the clock time EXACTLY as
                          printed for that place and only append its offset — never pre-convert
                          the time to another timezone yourself. If you cannot determine the
                          offset, omit it. Not every doc is a bill — it may be a payment due
                          date, appointment, flight departure, prescription/registration
                          expiry, or submission deadline. The date an email was SENT is NOT
                          the due date. If the deadline is in WORDS (e.g. "within 90 days of
                          the exam"), COMPUTE the actual calendar date, return THAT computed
                          date (not the date it's measured from), and add "dueDate" to
                          lowConfidenceFields. YEAR: documents often omit or abbreviate the
                          year — pick the year that makes the date make sense relative to TODAY
                          (given in the user message); for an upcoming deadline/appointment use
                          the current or next future year, and NEVER return a past year (e.g.
                          2023) for an action still to be done.
          accountNumber : the ONE identifier the reader needs to ACT on this — to pay it,
                          look it up, reference it on a call, or dispute it. Pick the
                          actionable id for whatever the document is: a bill's account number,
                          a ticket/summons number, a claim or case number, a confirmation /
                          booking code, an application receipt number. Prefer it over a passive
                          descriptor (e.g. on a ticket use the SUMMONS / ticket number you pay
                          with — NOT the violation code like "4-08(j)(3)" (the rule cited), and
                          not the license plate or VIN). null if none.
          accountLabel  : what accountNumber is CALLED on the document, in \(language.promptName)
                          — e.g. "Confirmation code", "Account number", "Summons number", "Case
                          number", "Policy number". This is the heading shown next to it, so name
                          it for what it actually is (a flight/hotel/order confirmation or booking
                          code is a "Confirmation code", NOT a generic "Reference"). null if
                          accountNumber is null.
          otherIDs      : other identifiers that genuinely help the reader act or follow up,
                          as an array of {"label","value"} objects — claim #, case #,
                          sticker / decal #, confirmation #, policy #, member #. Write each
                          LABEL in \(language.promptName) (keep universal abbreviations like
                          VIN, EIN, SSN, ITIN as-is). SKIP passive descriptors the reader won't
                          act on (VIN, make/model, plate) UNLESS they're actually needed to
                          pay/dispute. Always capture claim and policy numbers. For ANY ticket,
                          citation, fine, or court/agency notice, ALWAYS capture the SUMMONS /
                          TICKET number — the unique number used to PAY or DISPUTE (often 8–10
                          digits). That is NOT the violation code/section (e.g. "4-08(j)(3)",
                          the rule cited); if both appear, the summons number is the key id and
                          you may add the violation code as a separate labeled entry. [] if none.
          category      : EXACTLY one of these 9 lowercase words and NOTHING else:
                          utility, finance, housing, medical, personal, government, auto, work, other.
                          Travel, flights, appointments, and personal errands are "personal".
                          Use "auto" for anything about a VEHICLE — car registration/renewal,
                          auto insurance, a vehicle repair or service invoice. Use "government"
                          for tickets, fines, DMV/court letters, and tax/immigration notices.
                          Never invent a category like "travel" or "insurance" — use one of the 9.
          summary       : in \(language.promptName). Say what this document is AND, when it is
                          a penalty / notice / decision / response to something, WHY they got
                          it or what triggered it — lead with the cause, not just the type.
                          This applies to ANY type: a fine (what rule was broken), a claim
                          denial (the stated reason), a fee (what it's for), a renewal/expiry
                          notice (what's lapsing). One illustration: not "a parking ticket for
                          $65" but "a $65 parking ticket because the registration sticker had
                          expired." For a self-explanatory document one plain sentence is
                          enough (e.g. "A flight from New York to Chicago, UA623, departing
                          June 25 at 8:05 AM"). Add more only for a term/situation the reader
                          likely won't understand. Add understanding; don't reword or pad.
          steps         : the concrete, ORDERED actions to FULLY resolve this, in
                          \(language.promptName). Think it all the way through to "done" and
                          list EVERY real action — including the ones the document only hints
                          at. Don't stop at the obvious payment. Example: a parking ticket for
                          an EXPIRED REGISTRATION is not done when the fine is paid — the steps
                          should pay the ticket AND renew the registration AND get/display the
                          new sticker or tag (and, where offered, print a temporary proof) so
                          the person isn't ticketed again tomorrow. Be specific and operational,
                          not vague — no "pay it" / "contact them". Err toward MORE, smaller,
                          concrete steps rather than a few broad ones: break a big action into
                          its real sub-steps (what to gather, where to go, what to do, what to
                          save), and explain HOW and WHERE to do each one (the exact site,
                          office, or method) — e.g. not "renew the registration" but "Renew your
                          vehicle registration at your state DMV (online or in person), then put
                          the new sticker on the windshield." When there is an ONLINE option, give it
                          as a step WITH the website/app (e.g. "Check in online at united.com,
                          or check in at the airport counter"), then real next steps (e.g.
                          "arrive ~2 hours early", "go through security", "find your gate").
                          For a bill: "Go to <site> and log in", "open the bill", "pay and
                          save the confirmation". Put the SPECIFIC action link in the step
                          that uses it — the direct pay / dispute / login / booking page (e.g.
                          "Pay online at nyc.gov/payparkingticket"), NOT a generic homepage and
                          NOT only in notes. Only include a URL you are confident is the real
                          official one; otherwise write: search "<agency> pay <thing>". When a
                          notice is a penalty for an underlying lapse, the steps must also fix
                          the cause (see ROOT CAUSE below), in the right order. If a step is a
                          phone call or visit AND \(language.promptName) is not English, add a
                          sub-step to ask for an interpreter in \(language.promptName). Use []
                          if nothing to do.
          notes         : short helpful side-info that is NOT an action — who to contact and
                          how, useful context, caveats, deadlines context. Phone numbers and
                          URLs welcome here. [] if none.
          siteURL       : a relevant URL if the document names one, else null
          repeats       : one of "monthly", "yearly", "every:N" (N = days), or null. Set a
                          cadence ONLY for a bill/charge that genuinely repeats on a schedule
                          (a regular monthly utility or subscription → "monthly"; an annual
                          renewal → "yearly"). Use null (one-off) for anything that does NOT
                          recur — a final/closing bill, a shut-off or move-out notice, a
                          deposit, a one-time repair invoice, a ticket, an appointment. Do
                          NOT mark something monthly just because it's a utility.
          confidence    : your overall confidence 0.0-1.0
          lowConfidenceFields : array of field names you are unsure about

        If the document shows interest charged, a late fee, or any penalty, treat it \
        as a likely missed or late payment: in notes, (a) gently note they may have \
        missed a payment, (b) suggest paying the full balance and setting a reminder \
        so it doesn't happen again, and (c) tell them they can call the company (use \
        any phone number shown) to ask for a one-time waiver or refund of the fee. \
        For a statement with a minimum payment, add a note that paying only the \
        minimum (and the minimum amount) accrues interest at the stated APR.

        ROOT CAUSE — when a document is a CONSEQUENCE of an underlying problem, the \
        steps should address BOTH the cause AND this document, in a sensible order. \
        Put the cause-fixing actions in `steps` (the checklist the user works \
        through) — NEVER leave them only in `notes`. A note that says "you should \
        also renew your registration" does not count; it must be an actual step. \
        This is a general principle across document types — e.g. a ticket for an \
        expired registration → renew the registration AND handle the ticket; a late \
        fee → pay AND set up autopay/reminders so it doesn't recur; a denied claim or \
        application → fix the stated reason AND resubmit/appeal; a shut-off notice → \
        pay AND confirm service is restored. Use conditional ("if … then …") steps \
        ONLY when there is a genuine fork (e.g. "if you already renewed, dispute with \
        proof; if not, pay before the deadline"). If the document has NO underlying \
        cause (an ordinary bill, an appointment, a receipt, a flight), just give the \
        normal steps — do NOT invent a cause or force a fork that isn't there.

        For a flight or travel document, steps should include checking in (online \
        AND at the airport counter), arriving ~2 hours early, going through security, \
        and finding the gate; put the flight number in otherIDs; and add a note on \
        how to check the live gate/status (the airline's website, or searching the \
        flight number). Set siteURL to the airline's site when known.

        If the text is unreadable or meaningless (gibberish, too garbled to tell \
        what it is), return ONE item with documentType "unknown", a short summary \
        saying you couldn't read it, steps [], and confidence below 0.2. Never \
        invent a document.

        Safety guardrails:
        - Do NOT tell the reader they legally, medically, or tax-wise "must" do \
          something unless the document itself says so — use "you may need to" or \
          "check whether".
        - Do NOT diagnose symptoms or give medical / legal / tax / immigration- \
          eligibility advice beyond what the document states; for symptoms or an \
          accident, point them to a doctor, urgent care, or 911 when appropriate.
        - For immigration, tax, or legal documents, SUMMARIZE and ORGANIZE — do \
          not interpret eligibility or outcomes the document doesn't state.
        - Never put a full SSN, bank password/PIN, full card number, or A-number \
          into any field — mask all but the last 4 (ordinary account / reference / \
          confirmation numbers are fine to keep).
        - If you are unsure what the document is, say so plainly and set a low \
          confidence rather than guessing.

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

        let tf = DateFormatter(); tf.dateFormat = "yyyy-MM-dd"; tf.locale = Locale(identifier: "en_US_POSIX"); tf.timeZone = .current
        let knownBlock = known.isEmpty ? "" : "\n\nFields already detected by exact rules (prefer these):\(known)"
        return "Today's date is \(tf.string(from: Date())) (use it to resolve missing or ambiguous years).\n\nOCR TEXT:\n\"\"\"\n\(text)\n\"\"\"\(knownBlock)"
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

// MARK: - Guide polish (Week 7)

extension OpenAIClient {
    // Best-effort: reword a deterministic guide checklist to read naturally for
    // this person and add a tip or two. Returns the base UNCHANGED on any
    // failure (no key, offline, bad JSON) — guides must never block on the model.
    func polish(_ base: ExtractionResult,
                context: String,
                language: ExplainLanguage = .english) async -> ExtractionResult {
        guard canCall, !base.steps.isEmpty else { return base }

        let system = """
        You rewrite a short checklist for someone who may not read English well, \
        making each step clearer and MORE detailed and practical. For each step, \
        spell out HOW and WHERE to do it and the concrete specifics that help them \
        actually finish it (where to go, what to bring, what to click, what to save), \
        in plain \(language.promptName). Keep the SAME checklist: the same NUMBER of \
        steps, in the same order, each still about its original action. Do NOT add, \
        remove, reorder, or merge steps; do NOT add new requirements, deadlines, fees, \
        websites, or form numbers that aren't already in the step; do NOT invent facts. \
        Keep any URLs exactly as given. Reply ONLY as JSON {"steps":[...]} in \
        \(language.promptName).
        """
        let user = "Situation: \(context)\nSteps:\n"
            + base.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let body = ChatRequest(
            model: polishModel, response_format: .init(type: "json_object"), temperature: 0.2, max_tokens: 800,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)])

        guard let httpBody = try? JSONEncoder().encode(body) else { return base }
        let req = request(body: httpBody)

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
        let steps = list("steps").map(ExtractionJSON.stripLeadingNumber)
        // Only accept polished steps if the COUNT is unchanged — otherwise the
        // milestone↔detail alignment breaks and an authored (safety) step could
        // silently vanish. On any mismatch keep the deterministic steps.
        // Notes are left exactly as authored — polish never adds its own.
        if steps.count == base.steps.count, !steps.contains(where: { $0.isEmpty }) {
            out.steps = steps
        }
        return out
    }
}
