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
    // The in-app language. Drives the whole UI, not just the AI's prose — see
    // AppLanguage. Watched here (the root) so a change re-renders every screen.
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    private var language: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

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
        // Signing in on a device that holds ANOTHER account's data. The only two
        // answers are both non-destructive: take it with you, or back out and
        // leave the phone untouched. (The old third option deleted everything
        // local; it's gone — see SyncCoordinator.cancelSignIn.)
        // "Items", not "to-dos": the count behind this is to-dos PLUS family
        // profiles (see localPersonalDataCount — a person's name left by another
        // account is personal data too). Someone with 2 profiles and no to-dos was
        // being told they had "2 to-dos", which is simply untrue.
        .alert("This device's data belongs to another account",
               isPresented: $sync.isShowingReconciliation,
               presenting: sync.pendingReconciliation) { r in
            Button("Move them to this account") {
                Task {
                    guard let id = account.account?.userID else { return }
                    try? await sync.keepLocalTasks(context: context, userID: id)
                }
            }
            Button("Not now — sign out", role: .cancel) {
                Task {
                    guard let id = account.account?.userID else { return }
                    await sync.cancelSignIn(userID: id)
                }
            }
        } message: { r in
            Text("The \(r.localCount) items saved on this device belong to a different account. Nothing has been uploaded. Move them to this account, or sign out and leave them exactly as they are.")
        }
        // The reconciliation choice couldn't be carried out. The question is still
        // pending, so dismissing this puts it straight back.
        .alert("We couldn't finish that", isPresented: $sync.reconciliationFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was changed on this device or in your account. Please try again.")
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
        // ── The in-app language, applied to the whole app ──────────────────
        // `environment(\.locale)` is the door SwiftUI's Text(LocalizedStringKey)
        // resolves through; AppLanguage.apply covers String(localized:) and
        // NSLocalizedString. Both are needed — neither one alone gets every
        // string on screen.
        .environment(\.locale, Locale(identifier: language.lprojCode))
        // Forces a full rebuild when the picker changes, so screens already
        // rendered in the old language re-resolve their strings instead of
        // waiting to be revisited. Without this the switch looks half-applied.
        .id(language)
        .onChange(of: explainLanguageRaw) { _, _ in AppLanguage.applyStoredPreference() }
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
