//  Recurrence.swift
//
//  How often a task repeats. The AI reads the cadence from the document
//  (e.g. "due monthly", "renews annually") and puts it here — we do NOT
//  hardcode "monthly" like the v3 spec did.
//
//  Wired into `ActionItem.recurrence` in Week 8: marking a recurring item done
//  spawns the next cycle (due date advanced by `nextDate(after:)`), and delete
//  is recurring-aware ("just this one" vs "this and all future").
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

    // The next due date one cycle after `date`. Used when a recurring item is
    // marked done (or skipped) to spawn the following occurrence.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .monthly:           return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:            return calendar.date(byAdding: .year, value: 1, to: date)
        case .everyNDays(let n): return calendar.date(byAdding: .day, value: n, to: date)
        }
    }
}
