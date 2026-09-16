//  SignInFailureTests.swift
//
//  AuthService writes the session to the KEYCHAIN the moment the Worker issues
//  it — before owner migration runs. So when setup then fails, rolling back the
//  store is not enough: that session is live AND persisted, and the next edit or
//  foreground would pass syncNow's checks (valid session, no pending question)
//  and sync an identity whose canonical-owner migration never completed.
//
//  Surviving relaunch is exactly why an in-memory "it failed" flag can't cover
//  this. The session has to actually be given back.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct SignInFailureTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func session(_ userID: String, token: String) -> AuthService.Session {
        AuthService.Session(token: token, userID: userID, plus: false, hasServerData: false)
    }

    // A coordinator that was never `configure`d has no ProfileStore, so
    // `requireProfiles()` throws inside afterSignIn's do/catch — a deterministic
    // way to drive the real failure path without having to make SwiftData fail.
    @Test func failedSetupLeavesNoUsableSession() async throws {
        defer { SessionStore.clear() }
        let ctx = try context()
        let coordinator = SyncCoordinator()          // deliberately not configured

        SessionStore.save(token: "token-from-worker", userID: "apple-sub-A")
        #expect(SessionStore.isAuthenticated)

        let account = AccountStore(defaults: UserDefaults(suiteName: "signin.\(UUID().uuidString)")!)
        account.signIn(Account(userID: "apple-sub-A", provider: .apple, name: "", email: ""))

        let outcome = await coordinator.afterSignIn(
            session: session("apple-sub-A", token: "token-from-worker"),
            context: ctx, account: account)

        #expect(outcome == .failed)
        // The LOCAL sign-out has to happen too, or the UI keeps showing a
        // signed-in account with nothing behind it. Passing the store in is what
        // makes this assertable — the old optional could silently no-op.
        #expect(!account.isSignedIn)
        // THE POINT: the session is gone, so nothing can sync with it — including
        // after a relaunch, which is what a mere in-memory flag would have missed.
        #expect(!SessionStore.isAuthenticated)
        #expect(SessionStore.token == nil)
        #expect(SessionStore.userID == nil)
    }

    // And the follow-on: with no session, a later lifecycle sync is a no-op rather
    // than a push of a half-migrated identity.
    @Test func syncNowDoesNothingAfterAFailedSetup() async throws {
        defer { SessionStore.clear() }
        let ctx = try context()
        let coordinator = SyncCoordinator()
        let account = AccountStore(defaults: UserDefaults(suiteName: "signin.\(UUID().uuidString)")!)
        account.signIn(Account(userID: "apple-sub-A", provider: .apple, name: "", email: ""))

        SessionStore.save(token: "token-from-worker", userID: "apple-sub-A")
        _ = await coordinator.afterSignIn(
            session: session("apple-sub-A", token: "token-from-worker"),
            context: ctx, account: account)
        #expect(!account.isSignedIn)

        // syncNow's own guard is `SessionStore.isAuthenticated`; with the session
        // abandoned it can't proceed, and nothing is recorded as having synced.
        await coordinator.syncNow(context: ctx, account: account)
        #expect(coordinator.lastSyncedAt == nil)
        #expect(!SessionStore.isAuthenticated)
    }
}
