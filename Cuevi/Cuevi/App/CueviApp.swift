//  CueviApp.swift
//
//  Entry point. Sets up the SwiftData store, the shared AppRouter, and the
//  notification system (categories + a delegate that handles taps/actions),
//  then shows RootTabView.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct CueviApp: App {
    @Environment(\.scenePhase) private var scenePhase
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

    // Versioned container (CueviSchemaV1 + migration plan): future model changes
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
                for: ActionItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    // Shared with SchemaVersioningTests (which points it at a temp file).
    static func versionedContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CueviSchemaV1.self)
        let config = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema,
                                  migrationPlan: CueviMigrationPlan.self,
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
                .onAppear { notificationDelegate.attach(router: router) }
                .task {
                    // Notification permission is now requested through the
                    // first-launch explainer (NotificationPrimerView via
                    // RootTabView), not silently here.
                    refreshAllReminders()
                    Metrics.flush()   // send any metric events not yet uploaded
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        refreshAllReminders()
                    } else if phase == .background {
                        Metrics.flush()   // catch events logged during this session
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
