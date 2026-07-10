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
    // My Settings has the opt-out. Photos never leave the device either way.
    static let savePhotoKey = "cuevi.savePhotoWithItem"
    static var savePhoto: Bool {
        UserDefaults.standard.object(forKey: savePhotoKey) as? Bool ?? true   // unset → on
    }
}
