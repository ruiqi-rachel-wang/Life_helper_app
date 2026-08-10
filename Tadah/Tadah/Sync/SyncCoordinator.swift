//  SyncCoordinator.swift
//
//  Decides WHEN to sync and handles the two moments that need a human answer
//  (Part 3, phase 3). SyncService does the mechanics; this owns the policy:
//
//  • After sign-in — reconcile this device's tasks with the account's:
//      – NEW account (server has nothing) → the device's tasks SEED the account.
//        Non-destructive, no prompt.
//      – EXISTING account + this device has tasks → snapshot a local backup
//        FIRST, then ask: add them to the account, or replace with the account's?
//        Either way the backup is kept, so nothing is unrecoverable.
//      – EXISTING account + empty device → just pull. No prompt.
//  • Signed out remotely — a free account signed in on another device revoked
//    this session (/sync returns 401). Say so plainly instead of failing quietly.
//
//  Sync runs on sign-in and on foreground/background. Per-edit live sync is a
//  later refinement; scene changes already cover "edit here, see it there".
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {

    // A pending "what should we do with this device's tasks?" question.
    struct Reconciliation: Identifiable {
        // Which question we're actually asking. They read similarly but the stakes
        // differ: `sameOwner` is merging your own two copies, `differentOwner` is
        // about to hand one person's tasks to another person's account.
        enum Kind: Equatable {
            case sameOwner          // this account's own tasks, on a device that also has some
            case differentOwner     // the device's tasks belong to a DIFFERENT account
        }
        let id = UUID()
        let localCount: Int
        let kind: Kind
    }

    // One app-wide instance so the central mutation points (ItemActions, which
    // has no SwiftUI environment) can nudge a sync — same pattern as
    // ReminderScheduler.shared. The UI still receives it via .environment().
    static let shared = SyncCoordinator()

    // What actually happened when someone signed in. Sign-in has two halves that
    // can succeed independently, and the UI must not claim the second one until it
    // is genuinely done — "backed up" shown before the first sync completed was a
    // promise the app hadn't kept yet.
    enum SignInOutcome: Equatable {
        case backedUp                  // session AND a full sync round trip completed
        case signedInLocally           // session obtained but sync didn't complete
        case awaitingReconciliation    // waiting for the user to answer the merge question
    }

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?
    // Set when a sync is requested while one is running, or when the server says it
    // has more pages. Drives one more pass instead of losing the request.
    private var needsAnotherPass = false
    // Which account the in-flight pass belongs to (nil when idle).
    private var syncingUserID: String?
    var pendingReconciliation: Reconciliation?
    // Set when the server revoked this session (free = one device at a time).
    var signedOutRemotely = false

    // Set once at launch so nudges can sync without a view handing them over.
    private weak var account: AccountStore?
    private var context: ModelContext?
    private var debounce: Task<Void, Never>?

    // How long to wait after an edit before syncing, so a burst of checkbox taps
    // becomes one request instead of ten.
    private let debounceSeconds: UInt64 = 3

    func configure(context: ModelContext, account: AccountStore) {
        self.context = context
        self.account = account
    }

    // A local edit happened — sync shortly, coalescing rapid changes. Safe to
    // call from anywhere; no-ops when signed out or not configured.
    func noteLocalChange() {
        guard context != nil, account?.account != nil, SessionStore.isAuthenticated else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(self?.debounceSeconds ?? 3)))
            guard !Task.isCancelled, let self, let context = self.context, let account = self.account else { return }
            await self.syncNow(context: context, account: account)
        }
    }

    // MARK: - sign-in reconciliation

    @discardableResult
    func afterSignIn(session: AuthService.Session, context: ModelContext) async -> SignInOutcome {
        let userID = session.userID
        // Counts PROFILES too. Family profiles are other people's names — they're
        // personal data just like tasks, so a device holding only profiles (or only
        // tasks) still has something that must not silently cross accounts.
        let localCount = localPersonalDataCount(in: context)

        // FIRST, before anything can push: do these items belong to someone else?
        // Local data isn't account-scoped, and sign-out leaves it on the device
        // on purpose, so "the device has tasks" does NOT mean "this account's
        // tasks". Auto-seeding here is how one person's to-dos ended up in the next
        // person's cloud backup. Never push without an explicit answer.
        if localCount > 0, LocalDataOwner.belongsToSomeoneElse(than: userID) {
            _ = try? TaskBackup.snapshot(from: context)
            pendingReconciliation = Reconciliation(localCount: localCount, kind: .differentOwner)
            return .awaitingReconciliation
        }

        guard session.hasServerData else {
            // Brand-new account, and the local items are either this account's or
            // unclaimed guest data: they become its starting set.
            LocalDataOwner.claim(userID)
            SyncService.resetWatermark(userID)
            return await run(context: context, userID: userID) ? .backedUp : .signedInLocally
        }

        // Existing account. Snapshot BEFORE anything can overwrite local state.
        // If the snapshot fails we still continue — but only down the additive
        // path (merge), never a destructive one.
        let backedUp = (try? TaskBackup.snapshot(from: context)) != nil

        if localCount == 0 {
            LocalDataOwner.claim(userID)
            // nothing to lose: just pull
            return await run(context: context, userID: userID) ? .backedUp : .signedInLocally
        } else if backedUp {
            pendingReconciliation = Reconciliation(localCount: localCount, kind: .sameOwner)
            return .awaitingReconciliation
        } else {
            // Couldn't back up → refuse to offer "replace"; merge is safe.
            LocalDataOwner.claim(userID)
            SyncService.resetWatermark(userID)
            return await run(context: context, userID: userID) ? .backedUp : .signedInLocally
        }
    }

    // "Add my tasks to the account" — push everything local, pull everything
    // remote, keep both. Purely additive. When the tasks came from a different
    // account this is the moment the person consented to moving them, so the claim
    // moves with them.
    func keepLocalTasks(context: ModelContext, userID: String) async {
        pendingReconciliation = nil
        LocalDataOwner.claim(userID)
        SyncService.resetWatermark(userID)
        await run(context: context, userID: userID)
    }

    // "Use the account's tasks" — drop this device's copies and take the
    // account's. The backup written in afterSignIn is retained, so this is
    // recoverable. Local items are removed WITHOUT tombstones, and pushing is
    // suppressed, so this never deletes anything from the account.
    func useAccountTasks(context: ModelContext, userID: String) async {
        pendingReconciliation = nil
        for item in localTasks(in: context) {
            ReminderScheduler.shared.cancel(itemID: item.id)
            context.delete(item)
        }
        for stone in (try? context.fetch(FetchDescriptor<TaskTombstone>())) ?? [] {
            context.delete(stone)      // don't echo pre-sign-in deletes at the account
        }
        // PROFILES TOO. Leaving them behind meant "start fresh on this account"
        // kept the previous account's family members — other people's names — and
        // pushed them into the new account on the first sync. The owner profile is
        // recreated by ProfileStore.ensureOwnerProfile, and the account's own
        // profiles arrive in the pull below.
        for profile in (try? context.fetch(FetchDescriptor<Profile>())) ?? [] {
            context.delete(profile)
        }
        for stone in (try? context.fetch(FetchDescriptor<ProfileTombstone>())) ?? [] {
            context.delete(stone)
        }
        LocalDataOwner.claim(userID)
        SyncService.suppressPush(userID)
        SyncService.resetCursor(userID)
        await run(context: context, userID: userID)
    }

    // MARK: - routine sync

    func syncNow(context: ModelContext, account: AccountStore) async {
        guard let userID = account.account?.userID, SessionStore.isAuthenticated else { return }
        guard pendingReconciliation == nil else { return }   // wait for the user's answer
        await run(context: context, userID: userID, account: account)
    }

    // MARK: - internals

    // Returns whether a full pass actually completed against the server, so
    // sign-in can say "backed up" only when it truly is.
    @discardableResult
    private func run(context: ModelContext, userID: String, account: AccountStore? = nil) async -> Bool {
        // A sync is already in flight. Don't just drop this request — remember that
        // something changed and run once more when the current pass finishes.
        // Dropping it meant an edit made during a long sync sat unsynced until the
        // next launch or backgrounding.
        guard !isSyncing else { needsAnotherPass = true; return false }
        // Which account this whole loop belongs to. Signing out (or into another
        // account) mid-flight must abandon it rather than apply one account's
        // response to the other's store.
        syncingUserID = userID
        isSyncing = true
        defer { isSyncing = false; syncingUserID = nil }

        var succeeded = false
        repeat {
            needsAnotherPass = false
            do {
                let outcome = try await SyncService.sync(context: context, userID: userID)
                lastError = nil
                lastSyncedAt = .now
                succeeded = true
                // The server had more than one page — keep going rather than leave
                // the device holding a partial view of the account.
                if outcome.hasMore { needsAnotherPass = true }
            } catch SyncService.SyncError.accountChanged {
                // The user signed out or switched accounts while this was in the
                // air. Nothing was applied; just stop. Not an error to show.
                return false
            } catch SyncService.SyncError.unauthorized {
                // Session revoked — this device was signed in elsewhere.
                SessionStore.clear()
                account?.signOut()
                signedOutRemotely = true
                return false
            } catch SyncService.SyncError.notConfigured, SyncService.SyncError.noSession {
                // No backend configured / not signed in yet: stay local, stay quiet.
                return false
            } catch {
                lastError = error.localizedDescription
                return false    // don't spin on a failing server
            }
        } while needsAnotherPass
        return succeeded
    }

    private func localTasks(in context: ModelContext) -> [ActionItem] {
        (try? context.fetch(FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample }))) ?? []
    }
    // Everything on this device that is personal and account-scoped: the user's
    // to-dos AND the family profiles (other people's names). Reconciliation counts
    // both, because either one crossing accounts is the same privacy failure.
    private func localPersonalDataCount(in context: ModelContext) -> Int {
        let tasks = (try? context.fetchCount(
            FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample }))) ?? 0
        // Only NON-owner profiles count: every account auto-creates its own owner,
        // so an owner-only device has nothing of anyone else's on it.
        let people = ((try? context.fetch(FetchDescriptor<Profile>())) ?? [])
            .filter { !$0.isOwner }.count
        return tasks + people
    }
}
