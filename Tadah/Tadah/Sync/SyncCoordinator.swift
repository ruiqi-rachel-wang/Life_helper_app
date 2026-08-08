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

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?
    // Set when a sync is requested while one is running, or when the server says it
    // has more pages. Drives one more pass instead of losing the request.
    private var needsAnotherPass = false
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

    func afterSignIn(session: AuthService.Session, context: ModelContext) async {
        let userID = session.userID
        let localCount = localTaskCount(in: context)

        // FIRST, before anything can push: do these items belong to someone else?
        // Local tasks aren't account-scoped, and sign-out leaves them on the device
        // on purpose, so "the device has tasks" does NOT mean "this account's
        // tasks". Auto-seeding here is how one person's to-dos ended up in the next
        // person's cloud backup. Never push without an explicit answer.
        if localCount > 0, LocalDataOwner.belongsToSomeoneElse(than: userID) {
            _ = try? TaskBackup.snapshot(from: context)
            pendingReconciliation = Reconciliation(localCount: localCount, kind: .differentOwner)
            return
        }

        guard session.hasServerData else {
            // Brand-new account, and the local items are either this account's or
            // unclaimed guest data: they become its starting set.
            LocalDataOwner.claim(userID)
            SyncService.resetWatermark(userID)
            await run(context: context, userID: userID)
            return
        }

        // Existing account. Snapshot BEFORE anything can overwrite local state.
        // If the snapshot fails we still continue — but only down the additive
        // path (merge), never a destructive one.
        let backedUp = (try? TaskBackup.snapshot(from: context)) != nil

        if localCount == 0 {
            LocalDataOwner.claim(userID)
            await run(context: context, userID: userID)      // nothing to lose: just pull
        } else if backedUp {
            pendingReconciliation = Reconciliation(localCount: localCount, kind: .sameOwner)
        } else {
            // Couldn't back up → refuse to offer "replace"; merge is safe.
            LocalDataOwner.claim(userID)
            SyncService.resetWatermark(userID)
            await run(context: context, userID: userID)
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

    private func run(context: ModelContext, userID: String, account: AccountStore? = nil) async {
        // A sync is already in flight. Don't just drop this request — remember that
        // something changed and run once more when the current pass finishes.
        // Dropping it meant an edit made during a long sync sat unsynced until the
        // next launch or backgrounding.
        guard !isSyncing else { needsAnotherPass = true; return }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsAnotherPass = false
            do {
                let outcome = try await SyncService.sync(context: context, userID: userID)
                lastError = nil
                lastSyncedAt = .now
                // The server had more than one page — keep going rather than leave
                // the device holding a partial view of the account.
                if outcome.hasMore { needsAnotherPass = true }
            } catch SyncService.SyncError.unauthorized {
                // Session revoked — this device was signed in elsewhere.
                SessionStore.clear()
                account?.signOut()
                signedOutRemotely = true
                return
            } catch SyncService.SyncError.notConfigured, SyncService.SyncError.noSession {
                // No backend configured / not signed in yet: stay local, stay quiet.
                return
            } catch {
                lastError = error.localizedDescription
                return          // don't spin on a failing server
            }
        } while needsAnotherPass
    }

    private func localTasks(in context: ModelContext) -> [ActionItem] {
        (try? context.fetch(FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample }))) ?? []
    }
    private func localTaskCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample }))) ?? 0
    }
}
