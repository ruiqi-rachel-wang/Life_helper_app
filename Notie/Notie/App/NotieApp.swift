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
        let container = try! ModelContainer(for: ActionItem.self)
        self.container = container

        ReminderScheduler.shared.registerCategories()
        notificationDelegate.container = container
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(router)
                .onAppear { notificationDelegate.attach(router: router) }
                .task { await ReminderScheduler.shared.requestAuthorization() }
        }
        .modelContainer(container)
    }
}
