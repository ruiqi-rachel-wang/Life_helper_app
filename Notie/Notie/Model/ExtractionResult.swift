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
struct DocID: Equatable {
    var label: String
    var value: String
}

struct ExtractionResult: Equatable {
    var documentType: String?          // "Utility bill", "Parking ticket"…
    var sender: String?                // "Con Edison"
    var senderShort: String?           // short form for chips, if any
    var amount: Decimal?
    var currency: String?              // ISO 4217, e.g. "USD"
    var dueDate: Date?
    var accountNumber: String?         // the primary identifier
    var otherIDs: [DocID]              // any additional identifiers
    var category: ItemCategory?        // utility / government / medical…
    var summary: String?               // 1–2 sentence plain-language explanation
    var steps: [String]                // 3–5 action steps
    var siteURL: URL?
    var repeats: Recurrence?           // nil = one-off; AI reads cadence from doc
    var confidence: Double             // 0–1 overall
    var lowConfidenceFields: Set<String>   // field names the user should double-check

    init(documentType: String? = nil,
         sender: String? = nil,
         senderShort: String? = nil,
         amount: Decimal? = nil,
         currency: String? = nil,
         dueDate: Date? = nil,
         accountNumber: String? = nil,
         otherIDs: [DocID] = [],
         category: ItemCategory? = nil,
         summary: String? = nil,
         steps: [String] = [],
         siteURL: URL? = nil,
         repeats: Recurrence? = nil,
         confidence: Double = 0,
         lowConfidenceFields: Set<String> = []) {
        self.documentType = documentType
        self.sender = sender
        self.senderShort = senderShort
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.accountNumber = accountNumber
        self.otherIDs = otherIDs
        self.category = category
        self.summary = summary
        self.steps = steps
        self.siteURL = siteURL
        self.repeats = repeats
        self.confidence = confidence
        self.lowConfidenceFields = lowConfidenceFields
    }

    // An empty result — used when OCR produced nothing, so we never call the
    // LLM on a blank page (the one real "skip the model" path in Week 5).
    static let empty = ExtractionResult(confidence: 0)
}
