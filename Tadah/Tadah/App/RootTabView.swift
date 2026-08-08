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
    // The saved store couldn't be opened, so this session is running in memory and
    // nothing typed now will persist. The file on disk is untouched (TadahApp
    // deliberately never deletes it), so the right advice is "update, don't retype".
    var storeLoadFailed = false

    @Environment(AppRouter.self) private var router
    @Environment(TourGuide.self) private var tourGuide
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AccountStore.self) private var account
    @Environment(\.modelContext) private var context
    // Whether we've shown the first-launch notification explainer yet.
    @AppStorage("didAskNotifications") private var didAskNotifications = false
    // Whether the first-run tour has been seen (the empty Inbox can call
    // tourGuide.start() directly to replay it via "Show me how Tadah works").
    @AppStorage("didShowWelcomeTour") private var didShowWelcomeTour = false
    @State private var showNotificationPrimer = false
    @State private var showStoreFailure = false

    var body: some View {
        @Bindable var router = router
        @Bindable var sync = sync
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
        // Loud, because the alternative is someone re-entering everything and
        // losing it again at the next launch.
        .alert("Your saved to-dos couldn't be opened", isPresented: $showStoreFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing has been deleted — your to-dos are still saved on this phone, but this version of Tadah can't read them. Anything you add right now will not be kept. Please update to the latest version, and contact support if this keeps happening.")
        }
        .sheet(isPresented: $showNotificationPrimer) {
            NotificationPrimerView { didAskNotifications = true; showNotificationPrimer = false }
        }
        // Signing in on a device that already has tasks. A backup was written
        // first, so neither answer loses data. Two different questions share this
        // alert — see Reconciliation.Kind.
        .alert(sync.pendingReconciliation?.kind == .differentOwner
               ? "These to-dos belong to another account"
               : "You already have tasks on this device",
               isPresented: Binding(get: { sync.pendingReconciliation != nil },
                                    set: { if !$0 { sync.pendingReconciliation = nil } }),
               presenting: sync.pendingReconciliation) { r in
            Button(r.kind == .differentOwner
                   ? "Move them to this account"
                   : "Add them to my account") {
                Task {
                    if let id = account.account?.userID {
                        await sync.keepLocalTasks(context: context, userID: id)
                    }
                }
            }
            Button(r.kind == .differentOwner
                   ? "Start fresh on this account"
                   : "Use my account's tasks", role: .destructive) {
                Task {
                    if let id = account.account?.userID {
                        await sync.useAccountTasks(context: context, userID: id)
                    }
                }
            }
        } message: { r in
            // Plural handled by the String Catalog (en one/other), not an inline
            // "s" — languages like 中文 don't pluralize and a mid-sentence %@ can't
            // be translated cleanly.
            if r.kind == .differentOwner {
                // Nothing has been uploaded at this point, and nothing will be
                // unless the person picks the first button. Say so — they may be
                // holding someone else's phone.
                Text("The \(r.localCount) to-dos on this device were saved under a different account. They have not been uploaded. Move them to this account, or leave them out and start fresh? (A backup is saved either way.)")
            } else {
                Text("This device has \(r.localCount) tasks that aren't in your account yet. Add them to your account, or use your account's tasks instead? (A backup is saved either way.)")
            }
        }
        // Free accounts are one device at a time — the server revoked this session.
        .alert("Signed out on this device", isPresented: $sync.signedOutRemotely) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You signed in on another device. A free account can be used on one device at a time — Tadah Plus lets you use more. Your tasks are still saved here.")
        }
        .task {
            // Skip both one-time moments under UI tests (a system alert / a cover
            // block automation).
            guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
            // Ahead of the tour/primer: this one matters more than onboarding.
            if storeLoadFailed { showStoreFailure = true; return }
            // One thing at a time: the notification primer (a modal sheet) first;
            // the tour's first hint starts right away only when no sheet is coming,
            // otherwise when the sheet is dismissed (onChange below).
            await maybeShowNotificationPrimer()
            if !showNotificationPrimer, !didShowWelcomeTour { tourGuide.start() }
        }
        // Primer dismissed on first launch → now start the tour.
        .onChange(of: showNotificationPrimer) { was, isNow in
            if was, !isNow, !didShowWelcomeTour { tourGuide.start() }
        }
        // Reaching the Add tab lands the tour on the Add page's card — whether
        // the user tapped Next on the Add-tab card, tapped the tab themselves,
        // or jumped ahead during the welcome card.
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .add { tourGuide.catchUp(to: .create) }
        }
        // The tour just finished (all hints dismissed/completed) — remember that
        // so it doesn't restart on the next launch.
        .onChange(of: tourGuide.step) { old, new in
            if old != nil && new == nil { didShowWelcomeTour = true }
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
        .environment(TourGuide())
        .environment(AccountStore())
        .environment(PlusStore())
        .environment(SyncCoordinator())
        .environment(ProfileStore())
}
