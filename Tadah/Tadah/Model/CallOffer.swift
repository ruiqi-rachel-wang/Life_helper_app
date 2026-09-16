//  CallOffer.swift
//
//  Decides whether Tadah can offer to make a phone call about a document, what
//  number it would ring, and what it would say.
//
//  NOTHING NEW IS EXTRACTED FOR THIS. The scan prompt already produces
//  `StepDetail.script` ("what to say, ONLY when the step is a phone call"), and
//  the document's own identifiers are already parsed. So the offer is assembled
//  from data the app has been generating all along. The reviewed offer is saved
//  and synced with the to-do.
//
//  ⚠️ GETTING THE NUMBER RIGHT IS THE WHOLE JOB. A wrong number means Tadah rings
//  a stranger on the user's behalf, which is worse than not offering at all.
//
//  WHO DECIDES WHICH NUMBER: the model, not this file. The extraction now returns
//  `phone` — the one number the document prints to ring — because the model reads
//  the whole page and can see that "Customer Service: (516) 466-4416" is a phone
//  line and "Account Number: 4160250001" is not. Pattern-matching cannot: any
//  bare ten-digit run looks alike, which is exactly how the account number off a
//  real water bill ended up on the confirm screen on 2026-09-09.
//
//  WHAT THIS FILE STILL DOES is refuse to dial something undialable. The model
//  can mis-transcribe, and older to-dos predate the `phone` field entirely, so
//  every number — however it was found — is checked for NANP validity and against
//  the document's own identifiers before it is offered. The text scan below is
//  now only a FALLBACK for results with no `phone`.
//

import Foundation

nonisolated struct CallOffer: Codable, Equatable {
    /// As printed on the document, for display. The Worker normalizes it again.
    var phone: String
    /// Who is being called, if the document says. "Con Edison".
    var business: String?
    /// The suggested goal, in the user's language, editable before calling.
    var goal: String
    /// The document's own reference number, offered as an opt-in on the confirm
    /// page. Never sent unless the user ticks the box.
    var accountNumber: String?
    var accountLabel: String?
    /// What the agent could reasonably be authorised to agree to, derived from
    /// what KIND of document this is. A water bill has no appointments to book.
    var permissions: [CallPermission] = []

    /// The last four characters, for "Share my account number (···5512)".
    var accountTail: String? {
        guard let n = accountNumber?.filter({ !$0.isWhitespace }), n.count >= 4 else { return accountNumber }
        return String(n.suffix(4))
    }
}

// ── What Tadah may commit the user to ───────────────────────────────────────
//
// Derived from the document, not a fixed list. Offering "an appointment time" on
// a water bill is noise, and noise in an authorisation control is worse than
// noise anywhere else — it trains people to pick without reading.

nonisolated enum CallPermission: Codable, Hashable, Identifiable {
    case nothing
    case appointment
    case paymentPlan
    case extendDueDate
    case callback
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .nothing:       return String(localized: "Nothing")
        case .appointment:   return String(localized: "An appointment time")
        case .paymentPlan:   return String(localized: "A payment arrangement")
        case .extendDueDate: return String(localized: "A later due date")
        case .callback:      return String(localized: "A callback")
        case .custom:        return String(localized: "Something else…")
        }
    }

    /// The phrase handed to the agent. Empty means "commit to nothing".
    var authorisation: String {
        switch self {
        case .nothing:       return ""
        case .appointment:   return String(localized: "An appointment date and time")
        case .paymentPlan:   return String(localized: "A payment plan or instalment arrangement")
        case .extendDueDate: return String(localized: "A later due date or an extension")
        case .callback:      return String(localized: "A time for someone to call back")
        case .custom:        return ""
        }
    }

    /// The choices worth showing for this kind of document. `nothing` is always
    /// first and always the default; `custom` is always last.
    static func forDocument(category: ItemCategory?, hasAmount: Bool, hasDueDate: Bool) -> [CallPermission] {
        var middle: [CallPermission] = []
        switch category {
        case .medical:
            middle = [.appointment, .callback]
        case .government:
            middle = [.appointment, .callback]
        case .utility, .finance, .housing:
            // A bill's realistic outcomes are about money and timing.
            middle = [.paymentPlan, .extendDueDate, .callback]
        case .auto:
            middle = [.appointment, .paymentPlan, .callback]
        case .work, .personal, .other, .none:
            middle = [.callback]
        }
        // A document with money on it can always be negotiated about, whatever
        // the classifier decided it was.
        if hasAmount && !middle.contains(.paymentPlan) { middle.insert(.paymentPlan, at: 0) }
        if hasDueDate && !middle.contains(.extendDueDate) { middle.append(.extendDueDate) }
        return [.nothing] + middle + [.custom]
    }
}

// ── Finding the number ──────────────────────────────────────────────────────

extension CallOffer {

    /// One candidate number found in text, with everything needed to judge it.
    private struct Candidate {
        let raw: String          // as printed
        let digits: String       // 10 or 11 digits, no punctuation
        let formatted: Bool      // written like a phone number, not a bare run
        let nearPhoneWord: Bool  // "call", "phone", 致电, llamar… just before it
    }

    /// Words that mark the number after them as one to ring. Deliberately
    /// multilingual: the scan writes its steps in the user's language, so an
    /// English-only list would score every Chinese and Spanish step at zero.
    static let phoneWords = [
        "call", "phone", "tel", "telephone", "dial", "contact", "hotline", "toll-free",
        "电话", "致电", "拨打", "打电话", "联系",
        "llame", "llamar", "teléfono", "telefono", "marque", "contacte",
    ]

    /// Is this a structurally valid North American number we would dial?
    /// Mirrors `phoneIsCallable` in the Worker — the client must not offer a
    /// number the server is going to refuse.
    static func isValidNANP(_ digits: String) -> Bool {
        var d = digits
        if d.count == 11, d.hasPrefix("1") { d = String(d.dropFirst()) }
        guard d.count == 10, d.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return false }
        let npa = Array(d.prefix(3)), nxx = Array(d.dropFirst(3).prefix(3))
        // Area code and exchange both start 2-9. This is what rules out the
        // water bill's account number 416-025-0001: an exchange of "025".
        guard npa[0] >= "2", nxx[0] >= "2" else { return false }
        guard !(npa[1] == "1" && npa[2] == "1") else { return false }   // N11
        guard String(npa) != "900", String(nxx) != "976" else { return false }  // premium
        return true
    }

    /// Every plausible number in a piece of text, with context noted.
    private static func candidates(in text: String) -> [Candidate] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var found: [Candidate] = []

        // A phone number as a HUMAN writes one: parenthesised area code, or
        // groups separated by dashes/dots/spaces, optionally +1 / 1- in front.
        let formattedPattern = #"(?:\+?1[\s.\-]?)?(?:\(\d{3}\)[\s.\-]?|\d{3}[\s.\-])\d{3}[\s.\-]\d{4}"#
        // The same digits with nothing separating them. Far weaker evidence —
        // this is the shape an account number also has.
        let barePattern = #"(?<!\d)(?:\+?1)?\d{10}(?!\d)"#

        for (pattern, isFormatted) in [(formattedPattern, true), (barePattern, false)] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
                let digits = raw.filter(\.isNumber)
                guard isValidNANP(digits) else { continue }
                // Skip a bare run we already caught in formatted form.
                if !isFormatted && found.contains(where: { $0.digits == digits }) { continue }

                // Look back a short way for a word that means "ring this".
                let lookbackStart = max(0, m.range.location - 40)
                let before = ns.substring(with: NSRange(location: lookbackStart,
                                                       length: m.range.location - lookbackStart)).lowercased()
                let near = phoneWords.contains { before.contains($0) }
                found.append(Candidate(raw: raw, digits: digits, formatted: isFormatted, nearPhoneWord: near))
            }
        }
        return found
    }

    /// Normalized digits of every identifier the document carries, so a
    /// reference number can never be mistaken for a phone number.
    private static func identifierDigits(_ values: [String?]) -> Set<String> {
        Set(values.compactMap { $0 }.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty })
    }

    /// The best number in `texts`, or nil when none survives.
    ///
    /// `excluding` holds the document's own identifiers. This is the filter that
    /// mattered on the real water bill: the account number was structurally a
    /// valid-looking ten digits and appeared right next to the word "account".
    static func bestPhone(in texts: [String], excluding identifiers: [String?]) -> String? {
        let banned = identifierDigits(identifiers)
        var best: (score: Int, raw: String)?

        for (rank, text) in texts.enumerated() {
            for c in candidates(in: text) {
                // An identifier is never a phone number, however it is written.
                let tail10 = String(c.digits.suffix(10))
                if banned.contains(c.digits) || banned.contains(tail10) { continue }
                if banned.contains(where: { $0.contains(tail10) }) { continue }

                var score = 0
                if c.formatted      { score += 100 }   // strongest single signal
                if c.nearPhoneWord  { score += 50 }
                score += max(0, 10 - rank)             // earlier text field wins ties
                if best == nil || score > best!.score { best = (score, c.raw) }
            }
        }
        // A bare, unformatted run with no "call" word anywhere near it is not
        // evidence of a phone number — it is just ten digits, which is what an
        // account number looks like too. Require at least one real signal.
        guard let best, best.score >= 50 else { return nil }
        return best.raw
    }
}

// ── Building the offer ──────────────────────────────────────────────────────

extension CallOffer {

    /// Build an offer from a scan/guide result, or nil when there is nothing
    /// worth calling.
    static func from(_ result: ExtractionResult) -> CallOffer? {
        let identifiers: [String?] = [result.accountNumber] + result.otherIDs.map { $0.value as String? }

        // 1. THE MODEL'S ANSWER, if it gave one. Still validated: a number that
        //    cannot be dialled, or that is really an identifier, is dropped
        //    rather than trusted just because the model said it.
        if let modelPhone = result.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelPhone.isEmpty,
           let phone = accept(modelPhone, excluding: identifiers) {
            let goal = pairedGoal(phone: phone, steps: result.steps.enumerated().map { index, text in
                (text, index < result.detailedSteps.count ? result.detailedSteps[index].detail : nil)
            }) ?? defaultGoal(for: result)
            return offer(phone: phone, goal: goal, from: result)
        }

        // 2. FALLBACK — no `phone` on this result (an older scan, or the model
        //    left it null). Hunt through the steps as before.
        for (index, stepText) in result.steps.enumerated() {
            let detail: StepDetail? = index < result.detailedSteps.count
                ? result.detailedSteps[index].detail
                : nil

            // Most specific source first — `script` is what the app already
            // tells the user to say on the phone.
            let texts = [detail?.script ?? "", stepText, detail?.explanation ?? ""]
            guard let phone = bestPhone(in: texts, excluding: identifiers) else { continue }

            let goal = pairedGoal(phone: phone, steps: [(stepText, detail)]) ?? defaultGoal(for: result)
            guard !goal.isEmpty else { continue }

            return offer(phone: phone, goal: goal, from: result)
        }

        // FALLBACK: no step carried a number, but the document might still
        // print one — "Customer service: (516) 555-1234" often lands in the
        // notes or the summary rather than inside a step. Only worth doing when
        // a step actually asks the user to phone someone; otherwise a number
        // printed in the footer would turn every bill into a call offer.
        let callish = result.steps.first { step in
            phoneWords.contains { step.lowercased().contains($0) }
        }
        guard callish != nil else { return nil }
        let documentWide = result.notes + [result.summary ?? ""]
        guard let phone = bestPhone(in: documentWide, excluding: identifiers) else { return nil }
        return offer(phone: phone, goal: defaultGoal(for: result), from: result)
    }

    /// Validate a number we were HANDED (by the model, or later by the user).
    /// No formatting or nearby-word scoring — those exist to guess which number
    /// is a phone number, and that question is already answered here. Only
    /// "can this be dialled, and is it secretly an identifier" remains.
    static func phoneDigits(_ raw: String) -> String {
        // Match the Worker's extension handling before counting digits. Keep
        // the original text for display, but dial only the main number.
        let marker = raw.range(of: #"(?:\bext(?:ension)?\b|\bx)\.?\s*\d"#,
                               options: [.regularExpression, .caseInsensitive])
        let main = marker.map { String(raw[..<$0.lowerBound]) } ?? raw
        return main.filter(\.isNumber)
    }

    static func accept(_ raw: String, excluding identifiers: [String?]) -> String? {
        let digits = phoneDigits(raw)
        guard isValidNANP(digits) else { return nil }
        let banned = identifierDigits(identifiers)
        let tail10 = String(digits.suffix(10))
        guard !banned.contains(digits), !banned.contains(tail10) else { return nil }
        guard !banned.contains(where: { $0.contains(tail10) }) else { return nil }
        return raw
    }

    /// A script can be attached only to its own recipient. Multiple offices or
    /// multiple unlabelled call steps are ambiguous, so leave a neutral question.
    private static func pairedGoal(phone: String, steps: [(String, StepDetail?)]) -> String? {
        let target = String(phoneDigits(phone).suffix(10))
        var unnumbered: [String] = []
        var matched: [String] = []
        var hasOtherRecipient = false
        for (text, detail) in steps {
            let script = (detail?.script ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let goal = script.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : script
            let numbers = Set(candidates(in: [text, script, detail?.explanation ?? ""].joined(separator: " "))
                .map { String($0.digits.suffix(10)) })
            if numbers == [target] { if !goal.isEmpty { matched.append(goal) }; continue }
            if !numbers.isEmpty { hasOtherRecipient = true; continue }
            if !script.isEmpty || phoneWords.contains(where: { text.lowercased().contains($0) }) {
                unnumbered.append(goal)
            }
        }
        if matched.count == 1 { return matched[0] }
        return matched.isEmpty && !hasOtherRecipient && unnumbered.count == 1 ? unnumbered[0] : nil
    }

    /// When the document prints a number but no step says to ring it, the user
    /// may still want to. Give them something honest to edit.
    private static func defaultGoal(for result: ExtractionResult) -> String {
        let who = result.sender ?? result.senderShort ?? String(localized: "them")
        return String(localized: "Ask \(who) about this document.")
    }

    private static func offer(phone: String, goal: String, from result: ExtractionResult) -> CallOffer {
        CallOffer(
            phone: phone,
            business: result.sender ?? result.senderShort,
            goal: questionWithoutReference(goal, reference: result.accountNumber,
                                           who: result.sender ?? result.senderShort),
            accountNumber: result.accountNumber,
            accountLabel: result.accountLabel,
            permissions: CallPermission.forDocument(category: result.category,
                                                    hasAmount: result.amount != nil,
                                                    hasDueDate: result.dueDate != nil))
    }

    /// Same, for a saved to-do — so the card can travel with the task.
    static func from(_ item: ActionItem) -> CallOffer? {
        let identifiers: [String?] = item.otherIDs.map { $0.value as String? }
        if let stored = try? JSONDecoder().decode(CallOffer.self, from: Data(item.callOfferJSON.utf8)),
           accept(stored.phone, excluding: identifiers) != nil { return stored }

        for step in item.steps {
            let texts = [step.detail?.script ?? "", step.text, step.detail?.explanation ?? ""]
            guard let phone = bestPhone(in: texts, excluding: identifiers) else { continue }

            let who = item.sender.isEmpty ? String(localized: "them") : item.sender
            let goal = pairedGoal(phone: phone, steps: [(step.text, step.detail)])
                ?? String(localized: "Ask \(who) about this document.")
            guard !goal.isEmpty else { continue }

            // A saved item folds the primary accountNumber into otherIDs at index
            // 0 (see ActionItem.init(from:)), so the first id is that reference.
            let primary = item.otherIDs.first
            return CallOffer(
                phone: phone,
                business: item.sender.isEmpty ? nil : item.sender,
                goal: questionWithoutReference(goal, reference: primary?.value,
                                               who: item.sender.isEmpty ? nil : item.sender),
                accountNumber: primary?.value,
                accountLabel: primary?.label,
                permissions: CallPermission.forDocument(category: item.category,
                                                        hasAmount: item.amount != nil,
                                                        hasDueDate: item.dueDate != nil))
        }
        return nil
    }
}

// ── Keeping the reference number out unless it's shared ─────────────────────
//
// ⚠️ THE SWITCH MUST GOVERN WHAT IS SENT. The scan's phone script often names the
// account ("Ask about account 829105512347"), and that script became the
// question word for word. With "Share my account number" OFF the number still
// went to CALL-E and was read to a stranger. So the suggested question is built
// without it, and the request strips it again when the switch is off.

extension CallOffer {

    /// `text` with every spelling of `reference` removed: exactly as printed,
    /// and the same digits written plain, spaced, dashed or dotted. References
    /// under four digits are left alone; they can't be told apart from a date
    /// or an amount.
    static func removingReference(_ reference: String?, from text: String) -> String {
        guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              reference.count >= 4 else { return text }
        var out = text.replacingOccurrences(of: reference, with: "", options: .caseInsensitive)
        let target = reference.filter { $0 >= "0" && $0 <= "9" }
        if target.count >= 4, let runs = try? NSRegularExpression(pattern: #"#?\s?\d(?:[\s.\-]?\d)*"#) {
            let ns = out as NSString
            for match in runs.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed()
            where ns.substring(with: match.range).filter({ $0 >= "0" && $0 <= "9" }) == target {
                out = (out as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        // Close the gap the number leaves: no double spaces, no space before
        // punctuation.
        out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"[ \t]+([.,;:!?。，；：！？])"#, with: "$1", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// The suggested question, minus the reference. Never empty: a script that
    /// was only the number falls back to an honest question to edit.
    static func questionWithoutReference(_ goal: String, reference: String?, who: String?) -> String {
        let cleaned = removingReference(reference, from: goal)
        if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return cleaned }
        let name = who ?? String(localized: "them")
        return String(localized: "Ask \(name) about this document.")
    }
}

// ── Remembering a call across a relaunch ────────────────────────────────────
//
// The call outlives the screen: the Worker holds it, and the answer is written
// server-side whether or not the app is open. All the phone needs to keep is a
// pointer, so this is UserDefaults rather than a SwiftData column — no schema
// version bump for what is a transient breadcrumb.

// ── What the call came back with ────────────────────────────────────────────
//
// THE ANSWER BELONGS TO THE CARD, NOT TO THE TO-DO. A finished call used to be
// appended to `item.notes`, which quietly rewrote content the user had written
// themselves — the to-do stopped being theirs. This keeps the answer beside the
// to-do instead of inside it, so the card can show it again and nothing the user
// typed is ever edited by a phone call.
//
// UserDefaults for the same reason as `PendingCall` below: this is display state
// for one card, not to-do content, and a SwiftData column would mean a schema
// version plus a migration for something the user never edits. The trade is that
// it stays on this device and does not sync — acceptable for a record of a call
// this phone placed, and the to-do itself carries nothing that needs migrating.
nonisolated struct CallRecord: Codable, Equatable {
    /// Who was called, if the document said. Shown while the card is live.
    var business: String?
    var endedAt: Date
    /// Anything but "completed" — nobody reached, provider gave up, cancelled.
    var didFail: Bool
    /// The sentence a person can act on, in the user's own language.
    var detail: String?
    var summary: String?
    var agreed: String?
    var nextStep: String?
    var needsUserAction: Bool
}

nonisolated enum CallHistory {
    private static let key = "tadah.callResultByItem"

    private static var map: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func record(for itemID: UUID) -> CallRecord? {
        guard let data = map[itemID.uuidString] else { return nil }
        return try? JSONDecoder().decode(CallRecord.self, from: data)
    }

    static func save(_ record: CallRecord, for itemID: UUID) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        var m = map; m[itemID.uuidString] = data; map = m
    }

    static func forget(_ itemID: UUID) {
        var m = map; m.removeValue(forKey: itemID.uuidString); map = m
    }
}

nonisolated enum PendingCall {
    // v2 — was a bare [item: actionID] map. It now also carries the business
    // name, because whoever finishes the watch has to be able to write a
    // COMPLETE record, and a call picked up after the Review screen is gone has
    // no offer to read the name off. Any breadcrumb written by the old build is
    // simply not decodable and is ignored: at worst one in-flight call from
    // before this build is not picked up, which is what happened to every call
    // anyway before the app watched calls itself (CallCenter).
    private static let key = "tadah.pendingCallByItem.v2"

    struct InFlight: Codable, Equatable {
        var actionID: String
        /// Who is being rung, for the record the watcher will write.
        var business: String?
        /// When "Call now" was tapped. Keeps the to-do's timer honest across a
        /// relaunch, and tells the watcher how often to ask. Optional because a
        /// breadcrumb written by build 7 doesn't have it.
        var startedAt: Date? = nil
        /// The Tadah account that placed it. A call belongs to that account:
        /// it is only watched, and its answer only looked for, while that
        /// account is signed in. Nil on breadcrumbs from before 2026-09-16.
        var owner: String? = nil
        var uncertain: Bool? = nil

        /// Whether the account signed in now may watch this call.
        func belongs(to userID: String?) -> Bool { owner == nil || owner == userID }
    }

    private static var map: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Every call this phone started and has not yet seen the end of.
    static var all: [UUID: InFlight] {
        map.reduce(into: [:]) { out, pair in
            guard let id = UUID(uuidString: pair.key),
                  let call = try? JSONDecoder().decode(InFlight.self, from: pair.value)
            else { return }
            out[id] = call
        }
    }

    static func inFlight(for itemID: UUID) -> InFlight? {
        guard let data = map[itemID.uuidString] else { return nil }
        return try? JSONDecoder().decode(InFlight.self, from: data)
    }

    static func remember(_ actionID: String, business: String?, for itemID: UUID) {
        remember(InFlight(actionID: actionID, business: business, startedAt: .now), for: itemID)
    }

    static func remember(_ call: InFlight, for itemID: UUID) {
        guard let data = try? JSONEncoder().encode(call) else { return }
        var m = map; m[itemID.uuidString] = data; map = m
    }

    static func forget(_ itemID: UUID) {
        var m = map; m.removeValue(forKey: itemID.uuidString); map = m
    }
}
