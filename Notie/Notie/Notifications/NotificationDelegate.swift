//  NotificationDelegate.swift
//
//  Handles what happens when a reminder notification is interacted with:
//   • "Mark done"        → mark the item done in the store, cancel its reminders
//   • "Remind me later"  → snooze (fire again in 2 hours)
//   • tapping the banner → open the app to that item (via AppRouter)
//
//  It needs the shared ModelContainer to mutate items and the AppRouter to
//  route the UI; both are injected at launch by NotieApp.
//

import Foundation
import SwiftData
import UserNotifications

@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var container: ModelContainer?
    private(set) var router: AppRouter?

    // If a notification is tapped before the router is attached (cold launch),
    // remember the item here and route it the moment the router arrives.
    private var bufferedItemID: UUID?

    func attach(router: AppRouter) {
        self.router = router
        if let id = bufferedItemID {
            bufferedItemID = nil
            router.selectedTab = .inbox
            router.pendingItemID = id
        }
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Respond to a tap or an action button.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let idString = info[ReminderID.itemKey] as? String,
              let id = UUID(uuidString: idString) else { return }

        switch response.actionIdentifier {
        case ReminderID.markDone:
            markDone(id)
        case ReminderID.remindLater:
            ReminderScheduler.shared.snooze(
                itemID: id,
                title: response.notification.request.content.title)
        default:
            // Banner tapped (or "open") → route to the item. If the router
            // isn't attached yet (cold launch), buffer it for attach().
            if let router {
                router.selectedTab = .inbox
                router.pendingItemID = id
            } else {
                bufferedItemID = id
            }
        }
    }

    // Find the item in the store and mark it done, cancelling its reminders.
    private func markDone(_ id: UUID) {
        guard let container else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.id == id })
        guard let item = try? context.fetch(descriptor).first else { return }
        item.status = .done
        try? context.save()
        ReminderScheduler.shared.cancel(itemID: id)
    }
}
