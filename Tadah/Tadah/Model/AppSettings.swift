//  AppSettings.swift
//
//  Small app-wide user settings (UserDefaults keys) shared by several screens.
//  Pattern: a `…Key` constant for @AppStorage bindings in views, plus a plain
//  computed getter for non-view code. (Metrics + ReminderScheduler keep their
//  own keys the same way.)
//

import Foundation

enum AppSettings {
    // Keep the scanned document's photo on the saved item, shown at the end of
    // its Detail page so the user can always check the original. Default ON;
    // My Settings has the opt-out. (Photos aren't uploaded today — backing them
    // up to the account is a planned option, deliberately not a promise.)
    nonisolated static let savePhotoKey = "tadah.savePhotoWithItem"
    static var savePhoto: Bool {
        UserDefaults.standard.object(forKey: savePhotoKey) as? Bool ?? true   // unset → on
    }

    // The time of day a reminder fires when its item has NO specific time of its
    // own (a plain-date task, or the daily overdue nudge). Stored as minutes past
    // midnight; unset → 9:00am (540), the previous fixed default. A timed item
    // (e.g. a flight, reminded 3h before) keeps its own exact time and ignores this.
    nonisolated static let defaultReminderMinutesKey = "tadah.defaultReminderMinutes"
    nonisolated static let fallbackReminderMinutes = 9 * 60   // 9:00am
    static var defaultReminderMinutes: Int {
        (UserDefaults.standard.object(forKey: defaultReminderMinutesKey) as? Int) ?? fallbackReminderMinutes
    }
    static var defaultReminderHour: Int { defaultReminderMinutes / 60 }
    static var defaultReminderMinute: Int { defaultReminderMinutes % 60 }
}
