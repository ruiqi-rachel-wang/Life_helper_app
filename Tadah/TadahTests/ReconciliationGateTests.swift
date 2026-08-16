//  ReconciliationGateTests.swift
//
//  The cross-account question must survive the app being killed.
//
//  `pendingReconciliation` lives in memory, but the account and session are
//  already on disk by the time it's raised. So terminating the app before
//  answering used to discard the only thing standing between account A's data and
//  account B's cloud backup: relaunch produced a fresh coordinator with no pending
//  question, startup called syncNow, every guard passed, and A's to-dos uploaded
//  into B.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct ReconciliationGateTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "gate.\(UUID().uuidString)")!
    }

    // MARK: the store itself

    @Test func gateRoundTripsAndIsScopedToTheUser() {
        let d = defaults()
        ReconciliationGate.block(.question(localCount: 7), for: "userA", d)

        let saved: Int? = {
            if case .question(let count)? = ReconciliationGate.reason(for: "userA", d) { return count }
            return nil }()
        #expect(saved == 7)

        // A question raised for A must never apply to B.
        #expect(ReconciliationGate.reason(for: "userB", d) == nil)
        #expect(!ReconciliationGate.isBlocked(for: "userB", d))
    }

    @Test func gateClearsOnlyForTheUserItWasRaisedFor() {
        let d = defaults()
        ReconciliationGate.block(.question(localCount: 1), for: "userA", d)
        ReconciliationGate.block(.question(localCount: 2), for: "userB", d)

        ReconciliationGate.clear(for: "userA", d)
        #expect(!ReconciliationGate.isBlocked(for: "userA", d))
        #expect(ReconciliationGate.isBlocked(for: "userB", d))   // B's question stands
    }

    // A session must never become durable without a block already in place.
    // `adopt` is the single call that guarantees the ordering; anything that saves
    // a session by another route re-opens the window.
    @Test func adoptingASessionBlocksSyncBeforeThePasswordIsUsable() throws {
        defer { SessionStore.clear(); ReconciliationGate.clear(for: "apple-sub-Z") }
        ReconciliationGate.clear(for: "apple-sub-Z")

        try SessionStore.adopt(token: "tok-z", userID: "apple-sub-Z")

        #expect(SessionStore.isAuthenticated)
        // Blocked the moment the credential exists — not at some later step.
        #expect(ReconciliationGate.isBlocked(for: "apple-sub-Z"))
        #expect(ReconciliationGate.reason(for: "apple-sub-Z") == .setupIncomplete)
    }

    // THE CASE THE GATE ALONE CANNOT COVER.
    //
    // The gate is a UserDefaults value, written back to disk lazily; the session
    // is a Keychain value, written synchronously. A hard kill in that window can
    // lose the gate while KEEPING the credential — and the relaunch would then be
    // authenticated with nothing blocking a cross-account upload. `setupComplete`
    // rides inside the session record itself, so it survives whatever the gate
    // doesn't. Simulated here by deleting the gate out from under a live session.
    @Test func aLostGateIsStillCaughtByTheSessionsOwnMarker() throws {
        defer { SessionStore.clear(); ReconciliationGate.clear(for: "apple-sub-lost") }

        try SessionStore.adopt(token: "tok-lost", userID: "apple-sub-lost")
        // The gate evaporates (the UserDefaults write never reached disk).
        ReconciliationGate.clear(for: "apple-sub-lost")
        #expect(!ReconciliationGate.isBlocked(for: "apple-sub-lost"))

        // The credential is still there and still usable…
        #expect(SessionStore.isAuthenticated)
        // …but it still knows its own setup never finished.
        #expect(SessionStore.isSetupIncomplete)

        // And finishing setup clears it, so this can't wedge a legitimate sign-in.
        SessionStore.markSetupComplete()
        #expect(!SessionStore.isSetupIncomplete)
    }

    // MARK: the relaunch itself

    // THE REPRODUCTION. Ask the question, throw the coordinator away (as process
    // death does), build a fresh one, and confirm the question comes back rather
    // than the device quietly syncing.
    @Test func aFreshCoordinatorRestoresAnUnansweredQuestion() throws {
        let ctx = try context()
        let container = try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let accountDefaults = UserDefaults(suiteName: "gate.acct.\(UUID().uuidString)")!
        let account = AccountStore(defaults: accountDefaults)
        account.signIn(Account(userID: "apple-sub-B", provider: .apple, name: "", email: ""))
        let profiles = ProfileStore(defaults: UserDefaults(suiteName: "gate.prof.\(UUID().uuidString)")!)
        defer { ReconciliationGate.clear(for: "apple-sub-B") }

        // A question was raised for B and never answered, then the app died.
        ReconciliationGate.block(.question(localCount: 3), for: "apple-sub-B")

        // Relaunch: a brand-new coordinator, configured from scratch.
        let fresh = SyncCoordinator()
        fresh.configure(container: container, account: account, profiles: profiles)

        // The question is back, verbatim — not silently dropped.
        #expect(fresh.pendingReconciliation != nil)
        #expect(fresh.pendingReconciliation?.localCount == 3)
        _ = ctx
    }

    // THE DEFENCE-IN-DEPTH CASE. Here the in-memory copy is genuinely absent —
    // the gate is raised AFTER configure(), so `pendingReconciliation` is nil and
    // syncNow's own guard waves the request straight through. The only thing left
    // standing between the device and a cross-account upload is the persisted
    // check inside `run()`.
    @Test func aGateRaisedAfterConfigureStillBlocksSync() async throws {
        let ctx = try context()
        let container = try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let account = AccountStore(defaults: UserDefaults(suiteName: "gate.acct.\(UUID().uuidString)")!)
        account.signIn(Account(userID: "apple-sub-C", provider: .apple, name: "", email: ""))
        let profiles = ProfileStore(defaults: UserDefaults(suiteName: "gate.prof.\(UUID().uuidString)")!)
        defer { ReconciliationGate.clear(for: "apple-sub-C"); SessionStore.clear() }

        let coordinator = SyncCoordinator()
        coordinator.configure(container: container, account: account, profiles: profiles)
        #expect(coordinator.pendingReconciliation == nil)     // nothing in memory

        // Raised afterwards, so only the DISK flag knows about it.
        ReconciliationGate.block(.question(localCount: 4), for: "apple-sub-C")
        SessionStore.save(token: "tok-c", userID: "apple-sub-C")

        await coordinator.syncNow(context: ctx, account: account)

        #expect(coordinator.lastSyncedAt == nil)              // refused
        #expect(coordinator.pendingReconciliation != nil)     // and the question surfaced
    }

    // And the gate blocks syncing even if the in-memory copy were somehow missed:
    // syncNow refuses while a question is outstanding for this account.
    @Test func syncIsBlockedWhileAQuestionIsOutstanding() async throws {
        let ctx = try context()
        let container = try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let account = AccountStore(defaults: UserDefaults(suiteName: "gate.acct.\(UUID().uuidString)")!)
        account.signIn(Account(userID: "apple-sub-B", provider: .apple, name: "", email: ""))
        let profiles = ProfileStore(defaults: UserDefaults(suiteName: "gate.prof.\(UUID().uuidString)")!)
        defer { ReconciliationGate.clear(for: "apple-sub-B"); SessionStore.clear() }

        ReconciliationGate.block(.question(localCount: 3), for: "apple-sub-B")
        SessionStore.save(token: "tok", userID: "apple-sub-B")   // a usable session exists

        let fresh = SyncCoordinator()
        fresh.configure(container: container, account: account, profiles: profiles)
        await fresh.syncNow(context: ctx, account: account)

        #expect(fresh.lastSyncedAt == nil)          // nothing was synced
        #expect(fresh.pendingReconciliation != nil) // the question still stands
    }

    // "Add them to my account" must CLEAR the durable gate. It cleared only the
    // in-memory copy, so `run()` then saw the disk flag, refused to sync, and put
    // the question straight back — leaving that answer permanently unhonoured,
    // across every relaunch.
    @MainActor
    @Test func keepingLocalTasksClearsTheDurableGate() async throws {
        let ctx = try context()
        let container = try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let account = AccountStore(defaults: UserDefaults(suiteName: "gate.acct.\(UUID().uuidString)")!)
        account.signIn(Account(userID: "apple-sub-K", provider: .apple, name: "", email: ""))
        let profiles = ProfileStore(defaults: UserDefaults(suiteName: "gate.prof.\(UUID().uuidString)")!)
        defer { ReconciliationGate.clear(for: "apple-sub-K"); SessionStore.clear() }

        ReconciliationGate.block(.question(localCount: 2),
                                 for: "apple-sub-K")
        let coordinator = SyncCoordinator()
        coordinator.configure(container: container, account: account, profiles: profiles)
        #expect(coordinator.pendingReconciliation != nil)

        try await coordinator.keepLocalTasks(context: ctx, userID: "apple-sub-K")

        // Answered AND honoured: nothing left to re-ask.
        #expect(!ReconciliationGate.isBlocked(for: "apple-sub-K"))
        #expect(coordinator.pendingReconciliation == nil)
    }

    // Declining a cross-account move must be a true cancel: no task/profile
    // deletion, no usable session, and no stale question on the next sign-in.
    @Test func cancellingSignInLeavesLocalDataUntouched() async throws {
        let container = try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let task = ActionItem(title: "Keep me", category: .other)
        let person = Profile(name: "Ana", colorIndex: 0, isOwner: false)
        ctx.insert(task)
        ctx.insert(person)
        try ctx.save()

        let userID = "apple-sub-cancel"
        let account = AccountStore(defaults: UserDefaults(suiteName: "gate.acct.\(UUID().uuidString)")!)
        account.signIn(Account(userID: userID, provider: .apple, name: "", email: ""))
        let profiles = ProfileStore(defaults: UserDefaults(suiteName: "gate.prof.\(UUID().uuidString)")!)
        defer { ReconciliationGate.clear(for: userID); SessionStore.clear() }

        ReconciliationGate.block(.question(localCount: 2), for: userID)
        let coordinator = SyncCoordinator()
        coordinator.configure(container: container, account: account, profiles: profiles)

        await coordinator.cancelSignIn(userID: userID)

        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).map(\.id) == [task.id])
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).map(\.id) == [person.id])
        #expect(!SessionStore.isAuthenticated)
        #expect(!account.isSignedIn)
        #expect(!ReconciliationGate.isBlocked(for: userID))
        #expect(coordinator.pendingReconciliation == nil)
    }
}
