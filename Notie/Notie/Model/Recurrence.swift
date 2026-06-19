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

    // Month-based cadences need day-of-month anchoring (see nextDate); day-based
    // ones (weekly/biweekly/everyNDays) advance by a fixed number of days.
    var isMonthBased: Bool {
        switch self {
        case .monthly, .quarterly, .yearly: return true
        case .weekly, .biweekly, .everyNDays: return false
        }
    }

    // Localized label for display (follows the device language via the catalog).
    var label: String {
        switch self {
        case .weekly:            return String(localized: "Weekly")
        case .biweekly:          return String(localized: "Every 2 weeks")
        case .monthly:           return String(localized: "Monthly")
        case .quarterly:         return String(localized: "Every 3 months")
        case .yearly:            return String(localized: "Yearly")
        case .everyNDays(let n): return String(localized: "Every \(n) days")
        }
    }

    // The next due date one cycle after `date`. Used when a recurring item is
    // marked done (or skipped) to spawn the following occurrence.
    //
    // `anchorDay` is the day-of-month the SERIES is meant to land on (e.g. the
    // 31st). For month-based cadences we re-apply it (clamped to the target
    // month's length) so a short month doesn't permanently drift the series
    // earlier — Jan 31 → Feb 28 → *Mar 31*, not Mar 28. nil = keep `date`'s day.
    func nextDate(after date: Date, anchorDay: Int? = nil, calendar: Calendar = .current) -> Date? {
        switch self {
        case .weekly:            return calendar.date(byAdding: .day, value: 7,  to: date)
        case .biweekly:          return calendar.date(byAdding: .day, value: 14, to: date)
        case .everyNDays(let n): return calendar.date(byAdding: .day, value: n,  to: date)
        case .monthly:           return Self.addMonths(1,  to: date, anchorDay: anchorDay, calendar: calendar)
        case .quarterly:         return Self.addMonths(3,  to: date, anchorDay: anchorDay, calendar: calendar)
        case .yearly:            return Self.addMonths(12, to: date, anchorDay: anchorDay, calendar: calendar)
        }
    }

    // Add whole months, then snap back to the intended day-of-month (clamped to
    // the month's last day). Preserves the time-of-day so timed events keep it.
    private static func addMonths(_ months: Int, to date: Date,
                                  anchorDay: Int?, calendar: Calendar) -> Date? {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        guard let anchorDay else { return shifted }
        var comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: shifted)
        let lastDay = calendar.range(of: .day, in: .month, for: shifted)?.upperBound ?? 29
        comps.day = min(anchorDay, lastDay - 1)
        return calendar.date(from: comps) ?? shifted
    }
}
