//  TadahApp.swift
//
//  Entry point. Sets up the SwiftData store, the shared AppRouter, and the
//  notification system (categories + a delegate that handles taps/actions),
//  then shows RootTabView.
//

import SwiftUI
import SwiftData
import UserNotifications
import RevenueCat

@main
struct TadahApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var tourGuide = TourGuide()
    @State private var account = AccountStore()
    @State private var plus = PlusStore()
    @State private var sync = SyncCoordinator.shared
    @State private var profiles = ProfileStore()
    private let container: ModelContainer
    // True when the on-disk store couldn't be opened and this session is running
    // in memory. The file is left intact — see makeContainer.
    private let storeLoadFailed: Bool
    private let notificationDelegate = NotificationDelegate()

    init() {
        // Carry testers' metrics consent + install identity across the
        // Cuevi→Tadah UserDefaults-key rename before anything reads them.
        Metrics.migrateLegacyKeysIfNeeded()

        // RevenueCat (Tadah Plus billing). This is the PUBLIC Apple SDK key — it
        // is meant to ship inside the app and is safe in source control. The
        // *secret* key (sk_…) and the In-App Purchase .p8 never live here: they
        // stay in RevenueCat and in the Worker (REVENUECAT_SECRET).
        //
        // Purchases only work once, in RevenueCat: both products are attached to
        // the `Tadah Pro` entitlement (must match PlusStore.entitlementID and the
        // Worker's PLUS_ENTITLEMENT) and sit in an Offering marked Current.
        // Debug builds get the SDK's full log so a "coming soon" paywall can be
        // diagnosed from the device console: it names which product ids StoreKit
        // was asked for and why the fetch came back empty. Release stays .warn —
        // the debug stream is very chatty and would drown a shipping build's log.
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: "appl_NkpoJAXKXycQKzzekTUOmXaxedM")

        // Point every string lookup — ours, Apple's, and RevenueCat's — at the
        // picked language BEFORE the first view is built, otherwise launch renders
        // in the phone's language and only corrects itself on the next re-render.
        // Must follow Purchases.configure: the paywall locale override needs it.
        AppLanguage.applyStoredPreference()

        // One shared container, used by the UI and the notification delegate.
        let (container, failed) = Self.makeContainer()
        self.container = container
        self.storeLoadFailed = failed

        ReminderScheduler.shared.registerCategories()
        notificationDelegate.container = container
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    // Versioned container (TadahSchemaV1…V3 + migration plan): a model change
    // becomes a new Vn + a migration stage, so updates carry tester data forward.
    //
    // NOTHING HERE DELETES THE STORE. It used to: a failure to open wiped the file
    // and started fresh, which turns "this build has a migration bug" into "every
    // tester silently lost all their to-dos" — the one outcome the app must never
    // produce, and one nobody can undo. A store we can't open is kept untouched so
    // a later build can still migrate it, and the app runs on an in-memory store
    // for the session with a banner explaining what happened.
    //
    // `storeLoadFailed` drives that banner (RootTabView).
    private static func makeContainer() -> (container: ModelContainer, failed: Bool) {
        if let container = try? versionedContainer() { return (container, false) }
        // Do NOT touch the file on disk. In-memory keeps the app usable this
        // session; the real data is still there for a build that can open it.
        let memory = try! ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (memory, true)
    }

    // Shared with SchemaVersioningTests (which points it at a temp file).
    static func versionedContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TadahSchemaV3.self)
        let config = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema,
                                  migrationPlan: TadahMigrationPlan.self,
                                  configurations: [config])
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(storeLoadFailed: storeLoadFailed)
                .environment(router)
                .environment(tourGuide)
                .environment(account)
                .environment(plus)
                .environment(sync)
                .environment(profiles)
                .onAppear {
                    notificationDelegate.attach(router: router)
                    // So a scheduled notification fires at the time set for the
                    // person the to-do belongs to, not just the device default.
                    ReminderScheduler.shared.profileReminderMinutes = { [profiles] id in
                        profiles.reminderMinutes(for: id)
                    }
                }
                // Family profiles are what Plus is sold on, so the feature has to
                // switch off when the subscription ends — otherwise it's paid once
                // and kept forever. `ProfileStore` can't see `PlusStore`, so the
                // two are joined here, in the one place that owns both.
                //
                // Only lock once the tier is actually KNOWN: `isPlus` is false
                // until RevenueCat replies, and locking on that alone would blink
                // a paying family's profiles away at every launch.
                .onChange(of: plus.isPlus, initial: true) { _, _ in syncFamilyLock() }
                .onChange(of: plus.tierKnown) { _, _ in syncFamilyLock() }
                .onChange(of: account.isSignedIn) { _, _ in syncFamilyLock() }
                .task {
                    // GATE FIRST. `ensureOwnerProfile` mutates local identity —
                    // it can rename the owner and adopt unassigned items — so it
                    // must not run before the reconciliation state has been
                    // restored, or a device with an unanswered cross-account
                    // question would have its identity reshaped for the signing-in
                    // account before anyone consented.
                    sync.configure(container: container, account: account, profiles: profiles)
                    // …and SKIP identity work entirely while the gate is up.
                    // Restoring the gate isn't enough on its own: this call can
                    // rename the owner and adopt unassigned to-dos, so running it
                    // anyway reshaped one account's data for another before anyone
                    // had answered the question. It runs on the next launch, once
                    // the answer has been given.
                    if !sync.isBlockedPendingReconciliation {
                        profiles.ensureOwnerProfile(container.mainContext,
                                                    name: account.account?.displayName ?? "")
                    }
                    // Notification permission is now requested through the
                    // first-launch explainer (NotificationPrimerView via
                    // RootTabView), not silently here.
                    refreshAllReminders()
                    // Count the day BEFORE flushing, so today's open goes up in
                    // the same batch instead of waiting for the next launch.
                    Metrics.recordAppOpen()
                    Metrics.flush()   // send any metric events not yet uploaded
                    // Re-identify an ALREADY signed-in user to RevenueCat. Only the
                    // sign-in screen used to call logIn, so on every later launch
                    // RevenueCat fell back to an anonymous id — entitlements and the
                    // Worker's tier lookup then disagreed about who this is.
                    // Awaited before syncing, since /sync re-checks the tier.
                    if let userID = account.account?.userID {
                        _ = try? await Purchases.shared.logIn(userID)
                        await plus.refresh()
                    }
                    // (configure ran above, before any identity mutation.)
                    await sync.syncNow(context: container.mainContext, account: account)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        refreshAllReminders()
                        // Coming back from the background on a NEW day is a
                        // return visit and must count — a phone that never fully
                        // relaunches would otherwise look like a phone nobody
                        // opened. Same-day re-entry is a no-op.
                        Metrics.recordAppOpen()
                        // Pick up anything changed on another device while away.
                        Task { await sync.syncNow(context: container.mainContext, account: account) }
                    } else if phase == .background {
                        Metrics.flush()   // catch events logged during this session
                        // Push this session's edits before we lose foreground time.
                        Task { await sync.syncNow(context: container.mainContext, account: account) }
                    }
                }
        }
        .modelContainer(container)
    }

    // Dates keep moving even when an item is untouched. Rebuild schedules on
    // launch/foreground so an item that became overdue while the app was away
    // starts its repeating daily nudge. Goes through rescheduleAll so the
    // soonest reminders across ALL items win iOS's 64-pending-request budget.
    @MainActor
    // Fail OPEN: unlocked unless we positively know the tier is free. A RevenueCat
    // outage must not take a paying family's profiles away — the same rule the
    // Worker applies when it can't determine the tier.
    private func syncFamilyLock() {
        // Signed out = no family, full stop. Profiles are a property of an ACCOUNT
        // (they sync with it, they're capped by its tier), so showing a switcher
        // and per-person lists to someone with no account is offering a feature
        // that has nothing behind it — and it would leave a departed user's family
        // on screen for whoever picks the phone up next.
        guard account.isSignedIn else { profiles.familyUnlocked = false; return }
        profiles.familyUnlocked = plus.paidFeaturesUnlocked
    }

    private func refreshAllReminders() {
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<ActionItem>()) else { return }
        ReminderScheduler.shared.rescheduleAll(for: items)
    }
}
