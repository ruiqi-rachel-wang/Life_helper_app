//  RootTabView.swift
//
//  The tab-bar shell shown when the app launches. Holds the 4 main
//  destinations (Inbox, Add, Guides, Settings); tapping a tab swaps which
//  screen is shown above the bar. Tab titles are deliberately wordy
//  (tester feedback: "Guides" alone meant nothing) — say what each tab DOES.
//
//  Tab selection is driven by a shared AppRouter so screens can jump back to
//  the Inbox after saving. (A raised ＋ FAB was tried and dropped — a flat bar
//  reads cleaner with our four destinations.)
//

import SwiftUI
import SwiftData
import UserNotifications

struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    // Whether we've shown the first-launch notification explainer yet.
    @AppStorage("didAskNotifications") private var didAskNotifications = false
    @State private var showNotificationPrimer = false

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            InboxView()
                .tabItem { Label("To-Dos & Reminders", systemImage: "checklist") }
                .tag(AppRouter.Tab.inbox)

            CreateView()
                .tabItem { Label("Add To-Do", systemImage: "plus.circle.fill") }
                .tag(AppRouter.Tab.add)

            GuidesView()
                .tabItem { Label("Life Guides", systemImage: "books.vertical.fill") }
                .tag(AppRouter.Tab.guides)

            ProfileView()
                .tabItem { Label("My Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.profile)
        }
        .tint(Color.accent)
        .environment(router)
        .sheet(isPresented: $showNotificationPrimer) {
            NotificationPrimerView { didAskNotifications = true; showNotificationPrimer = false }
        }
        .task {
            // First launch: explain why reminders matter, THEN ask. Skip under UI
            // tests (a system alert blocks automation) and once we've asked.
            guard !didAskNotifications,
                  !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .notDetermined {
                showNotificationPrimer = true
            } else {
                didAskNotifications = true   // already decided in a past install/session
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
