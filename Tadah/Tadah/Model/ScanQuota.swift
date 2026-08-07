//  ScanQuota.swift
//
//  The per-tier limit on AI-powered actions — scans AND guides share ONE pool.
//  Two caps, both per device:
//    • a daily cap   — so a user can't burn the whole allowance in one sitting.
//    • a 30-day cap  — a rolling window (not a calendar month): "within the last
//      30 days, at most N".
//  Free vs Plus (pass `plus:` from PlusStore.isPlus):
//    • Free: 10/day, 20 per 30 days.
//    • Plus: 60/day, 300 per 30 days — effectively unlimited for real use, but a
//      real backstop so a runaway loop can't run up the OpenAI bill.
//  Local (UserDefaults) for now — a real per-user server limit comes with the
//  Cloudflare Worker. We store a timestamp per action and derive both caps from
//  it, pruning anything older than the window so the list stays tiny.
//

import Foundation

nonisolated enum ScanQuota {
    static let perDay = 10          // free
    static let perWindow = 20       // free, rolling 30 days
    static let perDayPlus = 60      // Plus
    static let perWindowPlus = 300  // Plus, rolling 30 days
    static let windowDays = 30

    static func dailyCap(plus: Bool) -> Int { plus ? perDayPlus : perDay }
    static func windowCap(plus: Bool) -> Int { plus ? perWindowPlus : perWindow }

    private static let eventsKey = "scanQuota.events"   // [Double] timeIntervalSinceReferenceDate

    private static var windowSeconds: TimeInterval { TimeInterval(windowDays) * 86_400 }

    // Timestamps within the rolling window, oldest first. Anything older is dropped.
    private static func events(now: Date, _ d: UserDefaults) -> [Double] {
        let cutoff = now.addingTimeInterval(-windowSeconds).timeIntervalSinceReferenceDate
        return (d.array(forKey: eventsKey) as? [Double] ?? []).filter { $0 > cutoff }
    }

    static func usedToday(now: Date = .now, _ d: UserDefaults = .standard) -> Int {
        let cal = Calendar.current
        return events(now: now, d).filter {
            cal.isDate(Date(timeIntervalSinceReferenceDate: $0), inSameDayAs: now)
        }.count
    }

    static func usedLast30Days(now: Date = .now, _ d: UserDefaults = .standard) -> Int {
        events(now: now, d).count
    }

    static func canScan(plus: Bool = false, now: Date = .now, _ d: UserDefaults = .standard) -> Bool {
        usedToday(now: now, d) < dailyCap(plus: plus) && usedLast30Days(now: now, d) < windowCap(plus: plus)
    }

    // Count one scan-or-guide. Call when an actual AI extraction/guide build runs.
    static func record(now: Date = .now, _ d: UserDefaults = .standard) {
        var kept = events(now: now, d)                       // already pruned to the window
        kept.append(now.timeIntervalSinceReferenceDate)
        d.set(kept, forKey: eventsKey)
    }

    // A user-facing reason when a scan/guide is blocked, else nil.
    static func blockedReason(plus: Bool = false, now: Date = .now, _ d: UserDefaults = .standard) -> String? {
        if usedToday(now: now, d) >= dailyCap(plus: plus) {
            return String(localized: "You've reached today's limit of \(dailyCap(plus: plus)) scans and guides. Try again tomorrow.")
        }
        if usedLast30Days(now: now, d) >= windowCap(plus: plus) {
            return String(localized: "You've used all \(windowCap(plus: plus)) scans and guides for the last 30 days. They free up as your earlier ones pass the 30-day mark.")
        }
        return nil
    }
}
