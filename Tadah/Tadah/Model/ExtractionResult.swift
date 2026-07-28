//  ExtractionResult.swift
//
//  THE critical shared type. Every layer of the scan pipeline produces this
//  one shape: the rule-based parser fills the exact fields it can (amount,
//  date, account #); the LLM fills the rest (summary, steps, category,
//  repeats); ExtractionService merges them into a single ExtractionResult;
//  and in Week 6 ReviewView just reads it. Keep this stable — it's the most
//  important interface in the codebase.
//
//  UI-free, like the rest of Model/: no Color, no SwiftUI. It mirrors the
//  spec's shape with two deliberate choices:
//   • `category` is our `ItemCategory` enum (not a free String) so it maps
//     straight to the icon/color without a translation layer.
//   • `repeats` uses the minimal `Recurrence` enum (see Recurrence.swift).
//

import Foundation

// A labeled identifier found on a document, e.g. label "eTicket", value
// "0162108515648". A single doc often carries several (a flight has a
// confirmation code AND an eTicket; a receipt has invoice + member numbers).
// `accountNumber` holds the primary one; `otherIDs` holds the rest.
nonisolated struct DocID: Equatable, Codable, Hashable {
    var label: String
    var value: String
}

nonisolated struct ExtractionResult: Equatable {
    var title: String?                 // short headline for the inbox row
    var documentType: String?          // "Utility bill", "Parking ticket"…
    var sender: String?                // "Con Edison"
    var senderShort: String?           // short form for chips, if any
    var amount: Decimal?
    var currency: String?              // ISO 4217, e.g. "USD"
    var dueDate: Date?
    var dueHasTime: Bool               // true if dueDate carries a specific time
                                       // (a flight/appointment), not just a day —
                                       // drives time-based reminders (Week 6)
    var accountNumber: String?         // the primary identifier
    var accountLabel: String?          // what that id is called on the doc (e.g. "Confirmation code")
    var otherIDs: [DocID]              // any additional identifiers
    var category: ItemCategory?        // utility / government / medical…
    var summary: String?               // what KIND of doc this is + plain context
    var steps: [String]                // concrete, ordered "do this now" actions
    // Guides only: the same steps but with optional StepDetail per milestone.
    // When non-empty it's authoritative on save; scans leave it [].
    var detailedSteps: [ChecklistStep]
    var notes: [String]                // side info / advice that isn't an action
    var siteURL: URL?
    var repeats: Recurrence?           // nil = one-off; AI reads cadence from doc
    var confidence: Double             // 0–1 overall
    var lowConfidenceFields: Set<String>   // field names the user should double-check
    // Editable reminder list while reviewing (parallels ActionItem.reminders), so the
    // Review and Detail edit screens share one editor. Empty + not customized → the
    // saved item uses smart defaults.
    var reminders: [ReminderItem] = []
    var remindersCustomized: Bool = false

    init(title: String? = nil,
         documentType: String? = nil,
         sender: String? = nil,
         senderShort: String? = nil,
         amount: Decimal? = nil,
         currency: String? = nil,
         dueDate: Date? = nil,
         dueHasTime: Bool = false,
         accountNumber: String? = nil,
         accountLabel: String? = nil,
         otherIDs: [DocID] = [],
         category: ItemCategory? = nil,
         summary: String? = nil,
         steps: [String] = [],
         detailedSteps: [ChecklistStep] = [],
         notes: [String] = [],
         siteURL: URL? = nil,
         repeats: Recurrence? = nil,
         confidence: Double = 0,
         lowConfidenceFields: Set<String> = [],
         reminders: [ReminderItem] = [],
         remindersCustomized: Bool = false) {
        self.title = title
        self.documentType = documentType
        self.sender = sender
        self.senderShort = senderShort
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.accountNumber = accountNumber
        self.accountLabel = accountLabel
        self.otherIDs = otherIDs
        self.category = category
        self.summary = summary
        self.steps = steps
        self.detailedSteps = detailedSteps
        self.notes = notes
        self.siteURL = siteURL
        self.repeats = repeats
        self.confidence = confidence
        self.lowConfidenceFields = lowConfidenceFields
        self.reminders = reminders
        self.remindersCustomized = remindersCustomized
    }

    // An empty result — used when OCR produced nothing, so we never call the
    // LLM on a blank page (the one real "skip the model" path in Week 5).
    static let empty = ExtractionResult(confidence: 0)

    // Translate every user-facing TEXT field to the app's language via the String
    // Catalog. Uses a plain dictionary lookup (Bundle.localizedString) rather than
    // String(localized:) so a literal "%" never triggers format parsing, and a
    // missing key returns the original. On the English development locale (which is
    // what unit tests run in) every lookup returns the original, so tests are
    // unaffected. Used for SENSITIVE guides, whose authored content is English in
    // code and never goes to the AI (translating) polish pass — this gives them an
    // on-device translation with no network and no privacy cost. Interpolated
    // strings (e.g. a state name spliced in) won't have a catalog key and stay as-is.
    func localized(_ language: ExplainLanguage) -> ExtractionResult {
        // Look up in the PICKED language's bundle (not the phone locale), so the
        // explanation-language picker controls guide content. Falls back to the main
        // bundle (development English) if that .lproj isn't present.
        let bundle = Bundle.main.path(forResource: language.lprojCode, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        func t(_ s: String) -> String {
            s.isEmpty ? s : bundle.localizedString(forKey: s, value: s, table: nil)
        }
        var r = self
        r.title = title.map(t)
        r.documentType = documentType.map(t)
        r.summary = summary.map(t)
        r.steps = steps.map(t)
        r.notes = notes.map(t)
        r.otherIDs = otherIDs.map { DocID(label: t($0.label), value: $0.value) }
        r.detailedSteps = detailedSteps.map { step in
            var s = step
            s.text = t(step.text)
            if var d = step.detail {
                d.explanation = t(d.explanation)
                d.miniChecklist = d.miniChecklist.map { SubStep(text: t($0.text), done: $0.done) }
                d.links = d.links.map { StepLink(label: t($0.label), url: $0.url) }
                d.script = t(d.script)
                d.needed = d.needed.map(t)
                d.fields = d.fields.map { SavedField(label: t($0.label), value: $0.value) }
                s.detail = d
            }
            return s
        }
        return r
    }
}
