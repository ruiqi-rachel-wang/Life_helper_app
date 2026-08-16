//  ReminderScheduler.swift
//
//  Wraps UNUserNotificationCenter — the iOS local-notification system.
//  Turns an ActionItem's reminderSchedule() (3d before / 1d before / due
//  day) into scheduled notifications, adds a repeating daily nudge once
//  overdue, and cancels them when the item is done or deleted.
//
//  This is the platform layer: it's allowed to know about ActionItem, but
//  the model stays free of UserNotifications. Notifications fire at 9am on
//  each reminder day; past times are skipped.
//
//  iOS keeps at most 64 pending local notifications PER APP and silently
//  drops the rest. rescheduleAll() (launch/foreground) therefore spends a
//  global budget soonest-first across ALL items, so with many dated items
//  it's the far-future reminders that wait (they get scheduled on a later
//  launch as their turn nears) — never the urgent ones. Per-item
//  reschedule(for:) stays unbudgeted: a single item is small, and the next
//  launch rebalances globally anyway.
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

    // Resolves the reminder time (minutes past midnight) for the person a to-do is
    // filed under. Injected by TadahApp, because the scheduler must not depend on
    // ProfileStore — and left nil in tests, where the device default applies.
    //
    // Without this the per-person time would be purely cosmetic: it would show in
    // the reminder editor while the notification that ACTUALLY fires still used the
    // device setting, which is the kind of half-wired feature that looks fine until
    // someone relies on it.
    var profileReminderMinutes: ((UUID?) -> Int)?

    private func minutes(for item: ActionItem) -> Int {
        profileReminderMinutes?(item.profileID) ?? AppSettings.defaultReminderMinutes
    }
    private let center = UNUserNotificationCenter.current()

    // "Hide details in notifications" (My Settings → Privacy): when on, banners
    // say "Tadah" instead of the item's title, and a generic body instead of
    // the due text / user note — nothing sensitive on the lock screen.
    nonisolated static let discreetKey = "tadah.notifications.discreet"
    private var discreet: Bool { UserDefaults.standard.bool(forKey: Self.discreetKey) }

    // Ask once for permission to show notifications.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // Register the "REMINDER" category so notifications show Mark done /
    // Remind me later buttons. Call once at launch.
    func registerCategories() {
        let markDone = UNNotificationAction(
            identifier: ReminderID.markDone, title: String(localized: "Mark done"), options: [])
        let remindLater = UNNotificationAction(
            identifier: ReminderID.remindLater, title: String(localized: "Remind me later"), options: [])
        let category = UNNotificationCategory(
            identifier: ReminderID.category,
            actions: [markDone, remindLater],
            intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // Reminders are an editable list, so notifications are id'd by index
    // ("<uuid>|r0", "r1", …). cancel() clears a generous range so a variable
    // count is always fully removed without an async fetch.
    private static let maxReminders = 32
    private static let legacyOverdueNudges = 14
    // Global pending-request budget for rescheduleAll — under iOS's 64 cap,
    // with headroom for snoozes and per-item edits made between launches.
    private static let globalBudget = 56

    // `includingSnooze: false` leaves a "Remind me later" request alone.
    //
    // A snooze is a one-off the USER asked for, and nothing here can recreate it —
    // it isn't derived from the item's dates, so once cancelled it's simply gone.
    // Rescheduling (launch, foreground, and now after every successful sync) was
    // therefore silently eating snoozes: someone taps "Remind me later", the app
    // syncs, and the reminder they just asked for never arrives. Deletion and
    // completion still clear it, because then there IS nothing to remind about.
    private func ids(for itemID: UUID, includingSnooze: Bool = true) -> [String] {
        var ids = (0..<Self.maxReminders).map { "\(itemID.uuidString)|r\($0)" }
        // Remove requests created by the old 14-one-shot implementation too.
        ids += (0..<Self.legacyOverdueNudges).map { "\(itemID.uuidString)|od\($0)" }
        ids.append("\(itemID.uuidString)|odDaily")   // repeating overdue nudge
        if includingSnooze { ids.append("\(itemID.uuidString)|snooze") }
        return ids
    }

    // Cancel + (re)schedule all reminders for ONE item (after an edit / save /
    // reopen). cancel() is synchronous (removes known ids), so the adds below
    // can't be undone by a late callback.
    func reschedule(for item: ActionItem) {
        // A done (or example) item keeps NOTHING, snooze included — there is
        // nothing left to be reminded about, and a stray "Snoozed reminder" for a
        // finished task is exactly the kind of nag that gets notifications turned
        // off entirely. Everything else keeps its snooze (see ids(for:)).
        guard wantsReminders(item) else { cancel(itemID: item.id); return }
        cancel(itemID: item.id, includingSnooze: false)

        let now = Date.now
        for (index, reminder) in item.effectiveReminders(defaultMinutes: minutes(for: item))
                .enumerated() where reminder.date > now {
            guard index < Self.maxReminders else { break }
            scheduleOneShot(item, index: index, reminder: reminder)
        }
        if item.isOverdue { scheduleOverdueNudge(item) }
    }

    // Cancel + reschedule EVERYTHING (launch / foreground), spending the global
    // budget soonest-first across all items — see the header comment.
    func rescheduleAll(for items: [ActionItem]) {
        // Same rule per item: keep the snooze only while the item still wants
        // reminders at all.
        for item in items {
            cancel(itemID: item.id, includingSnooze: !wantsReminders(item))
        }
        let active = items.filter(wantsReminders)
        var budget = Self.globalBudget

        // The daily overdue nudges first: they're the safety net, and there is
        // exactly one per overdue item.
        for item in active where item.isOverdue && budget > 0 {
            scheduleOverdueNudge(item)
            budget -= 1
        }

        // Then every future one-shot across all items, soonest first.
        let now = Date.now
        let upcoming = active
            .flatMap { item in
                item.effectiveReminders(defaultMinutes: minutes(for: item)).enumerated()
                    .filter { $0.element.date > now && $0.offset < Self.maxReminders }
                    .map { (item: item, index: $0.offset, reminder: $0.element) }
            }
            .sorted { $0.reminder.date < $1.reminder.date }
        for slot in upcoming.prefix(max(budget, 0)) {
            scheduleOneShot(slot.item, index: slot.index, reminder: slot.reminder)
        }
    }

    private func wantsReminders(_ item: ActionItem) -> Bool {
        item.status != .done && !item.isExample   // done never nags; nor do examples
    }

    // Remove every pending reminder belonging to this item. Synchronous —
    // removes the item's known identifiers directly (no fetch callback).
    func cancel(itemID: UUID, includingSnooze: Bool = true) {
        center.removePendingNotificationRequests(
            withIdentifiers: ids(for: itemID, includingSnooze: includingSnooze))
    }

    // "Remind me later" → fire again in 2 hours.
    func snooze(itemID: UUID, title: String) {
        let content = UNMutableNotificationContent()
        content.title = discreet ? String(localized: "Tadah") : title
        content.body = discreet ? Self.discreetBody() : String(localized: "Snoozed reminder")
        content.sound = .default
        content.categoryIdentifier = ReminderID.category
        content.userInfo = [ReminderID.itemKey: itemID.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "\(itemID.uuidString)|snooze", content: content, trigger: trigger))
    }

    // MARK: the two request builders

    private func scheduleOneShot(_ item: ActionItem, index: Int, reminder: ReminderItem) {
        let content = UNMutableNotificationContent()
        content.title = discreet ? String(localized: "Tadah") : item.title
        // A user-written note shows verbatim; otherwise compute a friendly body.
        // Discreet mode hides both — the note may be as sensitive as the title.
        content.body = discreet ? Self.discreetBody()
            : reminder.note.isEmpty
                ? body(fireDate: reminder.date, due: item.dueDate, hasTime: item.dueHasTime)
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

    // One repeating 9am request keeps nudging every day until Mark done /
    // Delete cancels it. Newly-overdue items are picked up when the app
    // refreshes all schedules on launch or foreground.
    private func scheduleOverdueNudge(_ item: ActionItem) {
        let content = UNMutableNotificationContent()
        content.title = discreet ? String(localized: "Tadah") : item.title
        content.body = discreet ? Self.discreetBody() : String(localized: "Overdue — still not done")
        content.sound = .default
        content.categoryIdentifier = ReminderID.category
        content.userInfo = [ReminderID.itemKey: item.id.uuidString]
        // Follows the OWNING PERSON's reminder time, like every other reminder.
        // This was hard-coded to the device default, so Mum's dated reminders
        // arrived at 9am while her overdue nudge came at the owner's 7pm — the
        // per-person setting looked half-applied because it was.
        let minutes = self.minutes(for: item)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60),
            repeats: true)
        center.add(UNNotificationRequest(
            identifier: "\(item.id.uuidString)|odDaily", content: content, trigger: trigger))
    }

    // MARK: helpers

    private static func discreetBody() -> String {
        String(localized: "A task needs your attention — open Tadah.")
    }

    // Friendly body computed from how far the fire date is before the due date.
    private func body(fireDate: Date, due: Date?, hasTime: Bool, calendar: Calendar = .current) -> String {
        guard let due else { return String(localized: "Reminder") }
        // "Starting soon" only fits a timed event near its exact time — a plain
        // due-day reminder should read "Due today", not "Starting soon".
        if hasTime, fireDate >= due.addingTimeInterval(-90 * 60) { return String(localized: "Starting soon") }
        let days = calendar.dateComponents([.day],
            from: calendar.startOfDay(for: fireDate),
            to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0:  return String(localized: "Overdue — still not done")
        case 0:     return String(localized: "Due today")
        case 1:     return String(localized: "Due tomorrow")
        default:    return String(localized: "Due in \(days) days")
        }
    }
}
