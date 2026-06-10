//  Recurrence.swift
//
//  How often a task repeats. The AI reads the cadence from the document
//  (e.g. "due monthly", "renews annually") and puts it here — we do NOT
//  hardcode "monthly" like the v3 spec did.
//
//  MINIMAL on purpose (Week 5). This enum exists now only so the shared
//  `ExtractionResult` type is stable. It is NOT yet wired into `ActionItem`
//  — that still uses `repeatsMonthly: Bool`. The real recurring behavior
//  (creating the next cycle on Mark done, recurring-aware delete) and the
//  migration of `ActionItem` onto this type both land in Week 7. Until
//  then this is just a value the parser/LLM can produce and tests can check.
//

import Foundation

// nil ExtractionResult.repeats = a one-off. A non-nil value = it repeats.
nonisolated enum Recurrence: Equatable, Codable {
    case monthly
    case yearly
    case everyNDays(Int)      // arbitrary cadence read from the document

    // Plain-English label for display / debugging.
    var label: String {
        switch self {
        case .monthly:           return "Monthly"
        case .yearly:            return "Yearly"
        case .everyNDays(let n): return "Every \(n) day\(n == 1 ? "" : "s")"
        }
    }
}
