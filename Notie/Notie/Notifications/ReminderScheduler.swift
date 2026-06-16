//  ReminderScheduler.swift
//
//  Wraps UNUserNotificationCenter — the iOS local-notification system.
//  Turns an ActionItem's reminderSchedule() (3d before / 1d before / due
//  day / overdue follow-up) into scheduled notifications, and cancels them
//  when the item is done or deleted.
//
//  This is the platform layer: it's allowed to know about ActionItem, but
//  the model stays free of UserNotifications. Notifications fire at 9am on
//  each reminder day; past times are skipped.
//

import Foundation
import UserNotifications

// Identifiers for the interactive notification + its action buttons.
enum ReminderID {
    static let category   = "REMINDER"
    static let markDone   = "MARK_DONE"
    static let remindLater = "REMIND_LATER"
    static let itemKey    = "itemID"
}

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private let center = UNUserNotificationCenter.current()

    // Ask once for permission to show notifications.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // Register the "REMINDER" category so notifications show Mark done /
    // Remind me later buttons. Call once at launch.
    func registerCategories() {
        let markDone = UNNotificationAction(
            identifier: ReminderID.markDone, title: "Mark done", options: [])
        let remindLater = UNNotificationAction(
            identifier: ReminderID.remindLater, title: "Remind me later", options: [])
        let category = UNNotificationCategory(
            identifier: ReminderID.category,
            actions: [markDone, remindLater],
            intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // Reminders are now an editable list, so notifications are id'd by index
    // ("<uuid>|r0", "r1", …). cancel() clears a generous range so a variable
    // count is always fully removed without an async fetch.
    private static let maxReminders = 32

    private func ids(for itemID: UUID) -> [String] {
        var ids = (0..<Self.maxReminders).map { "\(itemID.uuidString)|r\($0)" }
        ids.append("\(itemID.uuidString)|snooze")
        return ids
    }

    // Cancel + (re)schedule all reminders for an item. cancel() is synchronous
    // (removes known ids), so the adds below can't be undone by a late callback.
    func reschedule(for item: ActionItem) {
        cancel(itemID: item.id)
        guard item.status != .done else { return }

        let now = Date.now
        for (index, reminder) in item.effectiveReminders.enumerated() where reminder.date > now {
            guard index < Self.maxReminders else { break }
            let content = UNMutableNotificationContent()
            content.title = item.title
            // A user-written note shows verbatim; otherwise compute a friendly body.
            content.body = reminder.note.isEmpty
                ? body(fireDate: reminder.date, due: item.dueDate)
                : reminder.note
            content.sound = .default
            content.categoryIdentifier = ReminderID.category
            content.userInfo = [ReminderID.itemKey: item.id.uuidString]

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "\(item.id.uuidString)|r\(index)"
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // Remove every pending reminder belonging to this item. Synchronous —
    // removes the item's known identifiers directly (no fetch callback).
    func cancel(itemID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: ids(for: itemID))
    }

    // "Remind me later" → fire again in 2 hours.
    func snooze(itemID: UUID, title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Snoozed reminder"
        content.sound = .default
        content.categoryIdentifier = ReminderID.category
        content.userInfo = [ReminderID.itemKey: itemID.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "\(itemID.uuidString)|snooze", content: content, trigger: trigger))
    }

    // MARK: helpers

    private func at9am(_ day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }

    // Friendly body computed from how far the fire date is before the due date.
    private func body(fireDate: Date, due: Date?, calendar: Calendar = .current) -> String {
        guard let due else { return "Reminder" }
        if fireDate >= due.addingTimeInterval(-90 * 60) { return "Starting soon" }
        let days = calendar.dateComponents([.day],
            from: calendar.startOfDay(for: fireDate),
            to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0:  return "Overdue — still not done"
        case 0:     return "Due today"
        case 1:     return "Due tomorrow"
        default:    return "Due in \(days) days"
        }
    }

    #if DEBUG
    // Dev-only: fire a sample reminder a few seconds out so banner delivery
    // can be tested without waiting for a real due date. This notification has
    // no itemID, so action routing must be tested with a real scheduled item.
    func fireTestReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Test reminder"
        content.body = "This is what a Notie reminder looks like."
        content.sound = .default
        content.categoryIdentifier = ReminderID.category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "test-reminder", content: content, trigger: trigger))
    }
    #endif
}
