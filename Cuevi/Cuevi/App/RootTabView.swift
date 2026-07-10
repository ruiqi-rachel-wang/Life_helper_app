//  RootTabView.swift
//
//  The tab-bar shell shown when the app launches. Holds the 4 main
//  destinations (Inbox, Add, Guides, Profile); tapping a tab swaps which
//  screen is shown above the bar. Tab titles stay SHORT (they'd wrap/shrink
//  in the bar); each PAGE's masthead carries the long, self-explaining title
//  (e.g. 提醒待办事项 / To-Dos & Reminders) — Rachel's 2026-07-06 ask.
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
    // Whether the first-run walkthrough has been seen (the empty Inbox can reset
    // this to replay it via "Show me how Cuevi works").
    @AppStorage("didShowWelcomeTour") private var didShowWelcomeTour = false
    @State private var showNotificationPrimer = false
    @State private var showWelcome = false

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            InboxView()
                .tabItem { Label("To-Do", systemImage: "checklist") }
                .tag(AppRouter.Tab.inbox)

            CreateView()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(AppRouter.Tab.add)

            GuidesView()
                .tabItem { Label("Guides", systemImage: "books.vertical.fill") }
                .tag(AppRouter.Tab.guides)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.profile)
        }
        .tint(Color.accent)
        .environment(router)
        .fullScreenCover(isPresented: $showWelcome) {
            WelcomeTourView { didShowWelcomeTour = true; showWelcome = false }
        }
        .sheet(isPresented: $showNotificationPrimer) {
            NotificationPrimerView { didAskNotifications = true; showNotificationPrimer = false }
        }
        .task {
            // Skip both one-time moments under UI tests (a system alert / a cover
            // block automation).
            guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
            if !didShowWelcomeTour {
                showWelcome = true          // the notification primer follows once it closes
            } else {
                await maybeShowNotificationPrimer()
            }
        }
        // The tour just closed (or the Inbox asked to replay it by resetting the flag).
        .onChange(of: didShowWelcomeTour) { _, seen in
            if seen { Task { await maybeShowNotificationPrimer() } }
            else { showWelcome = true }
        }
    }

    // First launch: explain why reminders matter, THEN ask — after the walkthrough,
    // and only while iOS hasn't been asked yet.
    private func maybeShowNotificationPrimer() async {
        guard !didAskNotifications else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .notDetermined {
            showNotificationPrimer = true
        } else {
            didAskNotifications = true   // already decided in a past install/session
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
