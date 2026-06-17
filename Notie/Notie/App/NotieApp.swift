//  NotieApp.swift
//
//  Entry point. Sets up the SwiftData store, the shared AppRouter, and the
//  notification system (categories + a delegate that handles taps/actions),
//  then shows RootTabView.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct NotieApp: App {
    @State private var router = AppRouter()
    private let container: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        // One shared container, used by the UI and the notification delegate.
        let container = Self.makeContainer()
        self.container = container

        ReminderScheduler.shared.registerCategories()
        notificationDelegate.container = container
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    // Resilient container: if the on-disk store can't be opened (e.g. an
    // incompatible schema after a model change), recreate it instead of
    // hard-crashing the app at launch. Pre-1.0 we have no real user data —
    // samples reseed. NOTE: before shipping real updates, replace this with a
    // proper VersionedSchema + MigrationPlan so testers don't silently lose data.
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: ActionItem.self)
        } catch {
            deleteStore()
            if let fresh = try? ModelContainer(for: ActionItem.self) { return fresh }
            // Last resort so launch never crashes: an in-memory store.
            return try! ModelContainer(
                for: ActionItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    private static func deleteStore() {
        let base = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: base.path + suffix))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .onAppear { notificationDelegate.attach(router: router) }
                .task {
                    // Skip the permission prompt under UI tests so it can't block
                    // automation with a system alert.
                    if !ProcessInfo.processInfo.arguments.contains("-uitest") {
                        await ReminderScheduler.shared.requestAuthorization()
                    }
                }
        }
        .modelContainer(container)
    }
}
