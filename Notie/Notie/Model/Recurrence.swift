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
nonisolated enum Recurrence: Hashable, Codable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly
    case everyNDays(Int)      // arbitrary cadence read from the document by the AI

    // The presets offered in the REPEATS menu (everyNDays is AI-only).
    static let presets: [Recurrence] = [.weekly, .biweekly, .monthly, .quarterly, .yearly]

    // Plain-English label for display / debugging.
    var label: String {
        switch self {
        case .weekly:            return "Weekly"
        case .biweekly:          return "Every 2 weeks"
        case .monthly:           return "Monthly"
        case .quarterly:         return "Every 3 months"
        case .yearly:            return "Yearly"
        case .everyNDays(let n): return "Every \(n) day\(n == 1 ? "" : "s")"
        }
    }

    // The next due date one cycle after `date`. Used when a recurring item is
    // marked done (or skipped) to spawn the following occurrence.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .weekly:            return calendar.date(byAdding: .day,   value: 7,  to: date)
        case .biweekly:          return calendar.date(byAdding: .day,   value: 14, to: date)
        case .monthly:           return calendar.date(byAdding: .month, value: 1,  to: date)
        case .quarterly:         return calendar.date(byAdding: .month, value: 3,  to: date)
        case .yearly:            return calendar.date(byAdding: .year,  value: 1,  to: date)
        case .everyNDays(let n): return calendar.date(byAdding: .day,   value: n,  to: date)
        }
    }
}
