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
    private let container: ModelContainer
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
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: "appl_NkpoJAXKXycQKzzekTUOmXaxedM")

        // One shared container, used by the UI and the notification delegate.
        let container = Self.makeContainer()
        self.container = container

        ReminderScheduler.shared.registerCategories()
        notificationDelegate.container = container
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    // Versioned container (TadahSchemaV1 + migration plan): future model changes
    // become a V2 schema + a migration stage, so updates carry tester data
    // forward. The wipe-and-recreate fallback stays as a last resort against a
    // corrupt store file, but with versioned migrations a schema change should
    // never trigger it anymore.
    private static func makeContainer() -> ModelContainer {
        do {
            return try versionedContainer()
        } catch {
            deleteStore()
            if let fresh = try? versionedContainer() { return fresh }
            // Last resort so launch never crashes: an in-memory store.
            return try! ModelContainer(
                for: ActionItem.self, TaskTombstone.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    // Shared with SchemaVersioningTests (which points it at a temp file).
    static func versionedContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TadahSchemaV2.self)
        let config = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema,
                                  migrationPlan: TadahMigrationPlan.self,
                                  configurations: [config])
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
                .environment(tourGuide)
                .environment(account)
                .environment(plus)
                .environment(sync)
                .onAppear { notificationDelegate.attach(router: router) }
                .task {
                    // Notification permission is now requested through the
                    // first-launch explainer (NotificationPrimerView via
                    // RootTabView), not silently here.
                    refreshAllReminders()
                    Metrics.flush()   // send any metric events not yet uploaded
                    // Lets edits made anywhere (ItemActions, the editors) nudge a
                    // sync without threading the store through every call site.
                    sync.configure(context: container.mainContext, account: account)
                    await sync.syncNow(context: container.mainContext, account: account)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        refreshAllReminders()
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
    private func refreshAllReminders() {
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<ActionItem>()) else { return }
        ReminderScheduler.shared.rescheduleAll(for: items)
    }
}
