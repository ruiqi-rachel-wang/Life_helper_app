//  ScanQuota.swift
//
//  Caps AI-powered scans to protect the OpenAI bill: 10 per day, 50 per month,
//  per device. Local (UserDefaults) for now — a real per-user server limit comes
//  with the Cloudflare Worker. Counters are stamped with the current day/month
//  and reset automatically when the stamp rolls over.
//

import Foundation

nonisolated enum ScanQuota {
    static let perDay = 10
    static let perMonth = 50

    private static let dayCountKey  = "scanQuota.dayCount"
    private static let dayStampKey  = "scanQuota.dayStamp"
    private static let monthCountKey = "scanQuota.monthCount"
    private static let monthStampKey = "scanQuota.monthStamp"

    private static func stamp(_ format: String, _ now: Date) -> String {
        let f = DateFormatter(); f.dateFormat = format; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: now)
    }
    private static func dayStamp(_ now: Date) -> String { stamp("yyyy-MM-dd", now) }
    private static func monthStamp(_ now: Date) -> String { stamp("yyyy-MM", now) }

    // Count for the current period, or 0 if the stored stamp is stale (rolled over).
    private static func used(countKey: String, stampKey: String, current: String,
                             _ d: UserDefaults) -> Int {
        d.string(forKey: stampKey) == current ? d.integer(forKey: countKey) : 0
    }

    static func usedToday(now: Date = .now, _ d: UserDefaults = .standard) -> Int {
        used(countKey: dayCountKey, stampKey: dayStampKey, current: dayStamp(now), d)
    }
    static func usedThisMonth(now: Date = .now, _ d: UserDefaults = .standard) -> Int {
        used(countKey: monthCountKey, stampKey: monthStampKey, current: monthStamp(now), d)
    }

    static func canScan(now: Date = .now, _ d: UserDefaults = .standard) -> Bool {
        usedToday(now: now, d) < perDay && usedThisMonth(now: now, d) < perMonth
    }

    // Count one scan against both windows. Call when an actual AI extraction runs.
    static func record(now: Date = .now, _ d: UserDefaults = .standard) {
        let ds = dayStamp(now)
        d.set(used(countKey: dayCountKey, stampKey: dayStampKey, current: ds, d) + 1, forKey: dayCountKey)
        d.set(ds, forKey: dayStampKey)
        let ms = monthStamp(now)
        d.set(used(countKey: monthCountKey, stampKey: monthStampKey, current: ms, d) + 1, forKey: monthCountKey)
        d.set(ms, forKey: monthStampKey)
    }

    // A user-facing reason when scanning is blocked, else nil.
    static func blockedReason(now: Date = .now, _ d: UserDefaults = .standard) -> String? {
        if usedToday(now: now, d) >= perDay {
            return String(localized: "You've reached today's scan limit (\(perDay) a day). Try again tomorrow.")
        }
        if usedThisMonth(now: now, d) >= perMonth {
            return String(localized: "You've reached this month's scan limit (\(perMonth) a month).")
        }
        return nil
    }
}
