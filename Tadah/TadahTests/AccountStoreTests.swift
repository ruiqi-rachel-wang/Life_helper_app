//  AccountStoreTests.swift
//
//  AccountStore is pure state + UserDefaults persistence (no network), so we can
//  test sign-in/out, reload-from-disk, and the "keep the name Apple only gives
//  once" merge with an isolated UserDefaults suite.
//

import Testing
import Foundation
@testable import Tadah

@MainActor
struct AccountStoreTests {

    // A throwaway UserDefaults so tests never touch the real app domain.
    private func freshDefaults() -> UserDefaults {
        let suite = "tadah.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func apple(_ id: String, name: String = "", email: String = "") -> Account {
        Account(userID: id, provider: .apple, name: name, email: email)
    }

    @Test func signInThenReloadPersists() {
        let defaults = freshDefaults()
        let store = AccountStore(defaults: defaults)
        #expect(!store.isSignedIn)

        store.signIn(apple("u1", name: "Jing Wang", email: "jing@example.com"))
        #expect(store.isSignedIn)

        // A brand-new store on the SAME defaults reads the saved account back.
        let reloaded = AccountStore(defaults: defaults)
        #expect(reloaded.account?.userID == "u1")
        #expect(reloaded.account?.name == "Jing Wang")
        #expect(reloaded.account?.email == "jing@example.com")
    }

    @Test func signOutClearsButReloadStaysSignedOut() {
        let defaults = freshDefaults()
        let store = AccountStore(defaults: defaults)
        store.signIn(apple("u1", name: "Jing"))
        store.signOut()
        #expect(!store.isSignedIn)
        #expect(AccountStore(defaults: defaults).account == nil)
    }

    // Apple hands over the name/email only on the FIRST authorization; a later
    // sign-in of the same user comes back blank. We must keep the earlier values.
    @Test func reSignInKeepsFirstNameAndEmail() {
        let store = AccountStore(defaults: freshDefaults())
        store.signIn(apple("u1", name: "Jing Wang", email: "jing@example.com"))
        store.signIn(apple("u1"))   // same user, blank name/email
        #expect(store.account?.name == "Jing Wang")
        #expect(store.account?.email == "jing@example.com")
    }

    // A different user replaces the identity outright (no stale name carried over).
    @Test func differentUserReplacesIdentity() {
        let store = AccountStore(defaults: freshDefaults())
        store.signIn(apple("u1", name: "Jing"))
        store.signIn(apple("u2", name: "Mei"))
        #expect(store.account?.userID == "u2")
        #expect(store.account?.name == "Mei")
    }

    @Test func updateProfileEdits() {
        let store = AccountStore(defaults: freshDefaults())
        store.signIn(apple("u1", name: "Jing", email: "old@example.com"))
        store.updateProfile(email: "new@example.com")
        #expect(store.account?.name == "Jing")               // unchanged
        #expect(store.account?.email == "new@example.com")
    }

    // The LOCAL half of deletion (the no-backend path). Full deletion goes through
    // deleteAccountEverywhere, which erases the server copy first and throws if it
    // can't — that path needs the Worker, so it isn't unit-tested here.
    @Test func forgetLocallyForgetsIdentity() {
        let defaults = freshDefaults()
        let store = AccountStore(defaults: defaults)
        store.signIn(apple("u1", name: "Jing"))
        store.forgetLocally()
        #expect(!store.isSignedIn)
        #expect(AccountStore(defaults: defaults).account == nil)
    }

    @Test func displayNameAndInitialsFallback() {
        #expect(apple("u", name: "Jing Wang").displayName == "Jing Wang")
        #expect(apple("u", name: "Jing Wang").initials == "JW")
        // No name → fall back to email for the label, its first letter for initials.
        #expect(apple("u", email: "mei@example.com").displayName == "mei@example.com")
        #expect(apple("u", email: "mei@example.com").initials == "M")
    }

    // THREE WAYS OUT, ONE CLEANUP.
    //
    // Someone taps Log out, the server revokes the session, or the account is
    // deleted. All three end the session, so all three must forget the departed
    // user — the Profile page keeps a membership in memory otherwise and shows
    // the previous person's plan, renewal date and "Manage in the App Store" to
    // whoever picks the phone up next. Wiring the cleanup at one call site is
    // exactly how the other two got missed.
    @Test func everySignOutPathRunsTheCleanupHook() async {
        for path in ["signOutEverywhere", "signOutAfterSessionEnded"] {
            let store = AccountStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
            var ran = 0
            store.didSignOut = { ran += 1 }

            switch path {
            case "signOutEverywhere":        await store.signOutEverywhere()
            default:                         await store.signOutAfterSessionEnded()
            }
            #expect(ran == 1, "\(path) did not run didSignOut")
        }
    }

    // The plain synchronous signOut is the local half used by paths that cannot
    // await. It deliberately does NOT run the hook — its callers do, after the
    // RevenueCat logout they also own.
    @Test func theSynchronousSignOutLeavesTheHookToItsCaller() {
        let store = AccountStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        var ran = false
        store.didSignOut = { ran = true }
        store.signOut()
        #expect(!ran)
    }
}
