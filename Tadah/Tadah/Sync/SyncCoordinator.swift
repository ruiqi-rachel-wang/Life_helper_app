//  SyncCoordinator.swift
//
//  Decides WHEN to sync and handles the moments that need a human answer
//  (Part 3, phase 3). SyncService does the mechanics; this owns the policy:
//
//  • After sign-in — reconcile this device's tasks with the account's:
//      – NEW account (server has nothing) → the device's tasks SEED the account.
//        Non-destructive, no prompt.
//      – EXISTING account + this account's tasks → merge both copies.
//      – DIFFERENT account's tasks → ask before moving them; otherwise sign out
//        and leave the device untouched.
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
        let id = UUID()
        let localCount: Int
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
        case failed                    // couldn't set up safely; nothing was synced
    }

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date?
    // How many syncs have failed back-to-back without one succeeding. Reset by the
    // first success. Only the catch-all branch counts — a revoked session, a signed
    // -out account and "no backend configured" are handled states, not breakage.
    private(set) var failuresInARow = 0

    // IS BACKUP ACTUALLY BROKEN, as opposed to briefly offline?
    //
    // Sync is deliberately invisible: it runs on launch and on every
    // foreground/background transition, and a failed attempt just retries on the
    // next one, so a status light would be reporting on a chore the user was never
    // asked to do. That reasoning holds for TRANSIENT failures — and only those.
    //
    // A rejected request, an encoding failure, or data the server sends back that
    // this build can't read will fail exactly the same way on every retry. Left
    // silent, someone stays signed in for weeks believing their to-dos are backed
    // up while nothing has ever reached the server.
    //
    // Three consecutive failures is the line: a single blip, and the retry that
    // follows it, stay quiet; a fault that survives three separate attempts (a
    // launch and two foregrounds, at least) is not fixing itself and the user
    // deserves to know before they trust it with the only copy of their list.
    var backupIsStuck: Bool { failuresInARow >= 3 && lastError != nil }
    // Set when a sync is requested while one is running, or when the server says it
    // has more pages. Drives one more pass instead of losing the request.
    private var needsAnotherPass = false
    // Which account the in-flight pass belongs to (nil when idle).
    private var syncingUserID: String?
    // The QUESTION. Cleared only when a choice has actually been carried out.
    var pendingReconciliation: Reconciliation? {
        didSet { isShowingReconciliation = pendingReconciliation != nil }
    }
    // Whether the alert is on screen. Deliberately SEPARATE from the question:
    // SwiftUI drives this to false the moment a button is tapped, and tying the
    // question to it destroyed the very thing needed to ask again after a failure.
    var isShowingReconciliation = false
    // Set when a reconciliation choice couldn't be carried out. The question is
    // still pending and the alert is re-shown once this is acknowledged.
    var reconciliationFailed = false
    // Set when the server revoked this session (free = one device at a time).
    var signedOutRemotely = false

    // Set once at launch so nudges can sync without a view handing them over.
    // STRONG, like `profiles`: both are app-lifetime singletons held by TadahApp,
    // and a weak reference here would silently no-op the sign-out in
    // abandonSession — leaving the UI showing a signed-in account with no session.
    private var account: AccountStore?
    // STRONG, not weak. This is required by paths that delete data — the
    // coordinator is an app-lifetime singleton and the ProfileStore is held by
    // TadahApp for the whole run, so a weak reference bought nothing and risked
    // silently disappearing at exactly the wrong moment.
    private var profiles: ProfileStore?

    // Establishing the owner is not optional on any path that mutates data.
    // `try profiles?.bindOwner(...)` silently succeeded when the store was
    // missing, which would let a destructive reconciliation commit with no owner
    // at all. Fail before touching anything instead.
    private func requireProfiles() throws -> ProfileStore {
        // Deliberately NOT an assertionFailure. This is a handled, recoverable
        // state — the whole point is to fail safe before mutating anything — and
        // trapping here would turn that into a Debug crash and make the failure
        // path impossible to test.
        guard let profiles else { throw SyncError.notConfigured }
        return profiles
    }

    enum SyncError: Error { case notConfigured }
    private var container: ModelContainer?
    private var context: ModelContext?
    private var debounce: Task<Void, Never>?

    // How long to wait after an edit before syncing, so a burst of checkbox taps
    // becomes one request instead of ten.
    private let debounceSeconds: UInt64 = 3

    // True when this account may not have its local identity touched yet: a
    // question is outstanding, or sign-in setup never finished. Launch consults
    // this before doing anything account-derived.
    var isBlockedPendingReconciliation: Bool {
        guard let userID = account?.account?.userID else { return false }
        return ReconciliationGate.isBlocked(for: userID)
    }

    func configure(container: ModelContainer, account: AccountStore, profiles: ProfileStore) {
        self.container = container
        self.context = container.mainContext
        self.account = account
        self.profiles = profiles
        restorePendingReconciliation()
    }

    // A question asked before the app was killed is still unanswered. Without
    // this, relaunching cleared the gate and the very next syncNow would upload
    // one account's data into another's — see ReconciliationGate.
    private func restorePendingReconciliation() {
        guard let userID = account?.account?.userID,
              let reason = ReconciliationGate.reason(for: userID) else { return }
        switch reason {
        case .question(let localCount):
            pendingReconciliation = Reconciliation(localCount: localCount)
        case .setupIncomplete:
            // A session was issued but sign-in setup never finished. There is no
            // way to resume it safely — we don't know whether this device's data
            // was cleared for this account — so hand the session back and let the
            // user sign in again. Nothing local is deleted.
            guard let account, let token = SessionStore.token else {
                SessionStore.clear()
                ReconciliationGate.clear(for: userID)
                return
            }
            Task { [weak self] in
                await self?.abandonSession(token, account: account)
            }
        }
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

    // `account` is passed EXPLICITLY, not read from the stored property.
    //
    // The failure path has to sign the user out locally, and a stored optional —
    // even a strong one — is nil until `configure()` has run, which would let that
    // sign-out silently no-op at exactly the moment it matters. Taking it as a
    // parameter makes it impossible to reach this code without one.
    @discardableResult
    func afterSignIn(session: AuthService.Session,
                     context: ModelContext,
                     account: AccountStore) async -> SignInOutcome {
        let userID = session.userID
        // Counts PROFILES too. Family profiles are other people's names — they're
        // personal data just like tasks, so a device holding only profiles (or only
        // tasks) still has something that must not silently cross accounts.
        // A failed count must NOT be read as "this device is empty". We cannot
        // safely decide whether moving data is appropriate, so abandon this
        // session and leave the device untouched.
        let localCount: Int
        do {
            localCount = try localPersonalDataCount(in: context, forAccount: userID)
        } catch {
            await abandonSession(session.token, account: account)
            return .failed
        }

        // FIRST, before ANYTHING touches the data: do these items belong to
        // someone else? Local data isn't account-scoped, and sign-out leaves it on
        // the device on purpose, so "the device has tasks" does NOT mean "this
        // account's tasks". Auto-seeding here is how one person's to-dos ended up
        // in the next person's cloud backup. Never push, and never TRANSFORM,
        // without an explicit answer.
        //
        // bindOwner deliberately runs AFTER this check. It re-keys the owner
        // profile to the signing-in account, which on a device holding account A's
        // data would rewrite A's owner into B's — a change to one person's data
        // made on another person's behalf, before anyone consented to it.
        if localCount > 0, LocalDataOwner.belongsToSomeoneElse(than: userID) {
            raiseReconciliation(localCount: localCount, for: userID)
            return .awaitingReconciliation
        }

        // Safe now: the data is either this account's or unclaimed. Bind the owner
        // profile so every device agrees on one id instead of each pushing its own.
        //
        // NOT `try?`. bindOwner can mutate several profiles before a later child
        // fetch throws, so swallowing the error meant carrying on — and then
        // SYNCING — with a half-migrated identity: duplicate owners, or items
        // pointing at a profile id that no longer exists. Roll it back and stop.
        do {
            try requireProfiles().bindOwner(to: userID, in: context)
            try context.save()
        } catch {
            context.rollback()
            // AND GIVE UP THE SESSION.
            //
            // AuthService saves the session to the Keychain the moment the Worker
            // issues it — before any of this runs. Rolling back the store and
            // returning .failed left that session live and PERSISTED, so the very
            // next edit or foreground would sail through syncNow's checks (valid
            // session, no pending question) and sync an identity whose canonical-
            // owner migration never completed. Surviving relaunch is what makes an
            // in-memory flag insufficient here.
            await abandonSession(session.token, account: account)
            return .failed
        }

        guard session.hasServerData else {
            // Brand-new account, and the local items are either this account's or
            // unclaimed guest data: they become its starting set.
            LocalDataOwner.claim(userID)
            SyncService.resetWatermark(userID)
            SessionStore.markSetupComplete()           // durable half…
            ReconciliationGate.clear(for: userID)      // …then the fast path
            return await run(context: context, userID: userID) ? .backedUp : .signedInLocally
        }

        // SAME ACCOUNT → just merge. No question worth asking.
        //
        // There used to be a prompt here offering "use my account's tasks
        // instead", which deleted this device's copies. With that option gone
        // (see cancelSignIn) merging is the only safe answer, and it's what
        // someone signing into their OWN account expects: nothing is deleted,
        // both sides end up with everything.
        // SIGNING BACK IN vs SIGNING IN FOR THE FIRST TIME — different answers.
        //
        // If this device was ALREADY owned by this account, we're returning after a
        // sign-out, and anything changed in between was done while signed out.
        // Decision 2026-08-15: that work stays on the phone and is never uploaded,
        // so the account keeps exactly what it had. Advancing the watermark to now
        // is what "don't push what's already here" means — nothing is deleted, and
        // any FUTURE edit syncs normally.
        //
        // If the device was unclaimed (guest data from before any sign-in), the
        // opposite is right: those to-dos are this account's starting set, so push
        // them.
        let returningToOwnAccount = LocalDataOwner.current() == userID
        LocalDataOwner.claim(userID)
        if returningToOwnAccount {
            SyncService.suppressPush(userID)
        } else if localCount > 0 {
            SyncService.resetWatermark(userID)
        }
        SessionStore.markSetupComplete()               // durable half…
        ReconciliationGate.clear(for: userID)          // …then the fast path
        return await run(context: context, userID: userID) ? .backedUp : .signedInLocally
    }

    // "Add my tasks to the account" — push everything local, pull everything
    // remote, keep both. Purely additive. When the tasks came from a different
    // account this is the moment the person consented to moving them, so the claim
    // moves with them.
    func keepLocalTasks(context: ModelContext, userID: String) async throws {
        // Consent given — only now may the owner profile be re-keyed to this
        // account (see the note in afterSignIn). THROWING: a half-done identity
        // migration must not be followed by a sync that pushes the result.
        do {
            try requireProfiles().bindOwner(to: userID, in: context)
            try context.save()
        } catch {
            context.rollback()
            reconciliationFailed = true      // question stays pending…
            isShowingReconciliation = true   // …and comes back on screen
            throw error
        }
        // Every safety prerequisite is durable before the gate comes down: the
        // owner binding is saved above, the claim and watermark are written here.
        // The gate is the LAST persistent step — and it must actually happen, or
        // this path stays blocked on every relaunch, re-asking a question the user
        // already answered.
        LocalDataOwner.claim(userID)
        SyncService.resetWatermark(userID)
        SessionStore.markSetupComplete()
        ReconciliationGate.clear(for: userID)
        pendingReconciliation = nil
        // A retry that succeeds must also retract the failure alert, or SwiftUI
        // presents "we couldn't finish that" moments after it visibly finished.
        reconciliationFailed = false
        await run(context: context, userID: userID)
    }

    // "Not now" — DON'T take this device's data into the account.
    //
    // This replaces what used to be "Start fresh on this account", which deleted
    // every local task and profile. That option could not be made safe: a complete
    // backup is impossible because scanned PHOTOS are external-storage blobs that
    // never enter a TaskDTO, so replacement destroyed documents with no way back.
    // Adding a restore path to compensate only widened the surface (a restore is a
    // whole state transition — ownership, watermarks, tombstones, reminders — not a
    // file copy).
    //
    // So the escape hatch is now non-destructive: sign out and leave everything on
    // the phone exactly as it is. The person can sign back into the account that
    // owns this data, or clear it themselves, and nothing is lost either way.
    func cancelSignIn(userID: String) async {
        pendingReconciliation = nil
        isShowingReconciliation = false
        reconciliationFailed = false
        guard let account else {
            SessionStore.clear()
            ReconciliationGate.clear(for: userID)
            return
        }
        guard let token = SessionStore.token else {
            SessionStore.clear()
            await account.signOutAfterSessionEnded()
            ReconciliationGate.clear(for: userID)
            return
        }
        await abandonSession(token, account: account)
    }

    // MARK: - routine sync

    func syncNow(context: ModelContext, account: AccountStore) async {
        guard let userID = account.account?.userID, SessionStore.isAuthenticated else { return }
        guard pendingReconciliation == nil else { return }   // wait for the user's answer
        await run(context: context, userID: userID)
    }

    // MARK: - internals

    // Raise the question, in memory AND on disk, so killing the app can't discard
    // it and leave the next sync free to run.
    private func raiseReconciliation(localCount: Int,
                                     for userID: String) {
        ReconciliationGate.block(.question(localCount: localCount), for: userID)
        pendingReconciliation = Reconciliation(localCount: localCount)
    }

    // Drop a session we should never have kept: clear it locally FIRST so nothing
    // can use it (including after a relaunch), then best-effort revoke it on the
    // server. The local account is signed out too, so the UI can't show a
    // signed-in state with no usable session behind it.
    private func abandonSession(_ token: String, account: AccountStore) async {
        let userID = SessionStore.userID
        SessionStore.clear()
        await account.signOutAfterSessionEnded()
        // Only clear the gate after the credential is gone. A process death
        // between these operations therefore leaves either a blocked session or
        // no session, never an authenticated unblocked one.
        if let userID { ReconciliationGate.clear(for: userID) }
        // Best effort: the local state is already safe, and the session expires on
        // its own even if this never lands.
        try? await AuthService.logout(token: token)
    }


    // Returns whether a full pass actually completed against the server, so
    // sign-in can say "backed up" only when it truly is.
    @discardableResult
    private func run(context: ModelContext, userID: String) async -> Bool {
        // An authenticated sync REQUIRES the AccountStore, because a 401 has to be
        // able to sign the UI out. `run` used to take it as an optional and the
        // sign-in paths called it without one, so `account?.signOut()` silently did
        // nothing: the Keychain was cleared but the app went on showing a signed-in
        // account with no usable session. Refuse to run rather than get into that
        // state — `configure()` is called at launch, so this is never nil in
        // practice, and a missing one is a wiring bug worth failing loudly on.
        // Same reasoning as requireProfiles: refuse to run, don't trap.
        guard let account, let container else { return false }

        // THE PERSISTED GATE, checked at the last possible moment.
        //
        // Every sync path funnels through here, so this is the one place that
        // cannot be bypassed by a relaunch, a lifecycle event, or a nudge from an
        // edit. The in-memory `pendingReconciliation` is only the UI's copy; the
        // disk flag is what actually holds the line.
        if ReconciliationGate.isBlocked(for: userID) {
            restorePendingReconciliation()      // put the question back on screen
            return false
        }
        // AND THE KEYCHAIN'S OWN MARKER, for the case the gate can't cover.
        //
        // The gate is a UserDefaults value; the session is a Keychain value written
        // synchronously. A hard kill between the two can lose the gate and keep the
        // credential, and this pass would then run for a sign-in that never finished
        // reconciling — uploading whatever is on the phone. `setupComplete` rides
        // inside the session record itself, so it cannot be lost separately.
        if SessionStore.isSetupIncomplete {
            ReconciliationGate.block(.setupIncomplete, for: userID)   // restore the gate
            restorePendingReconciliation()
            return false
        }
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
                let outcome = try await SyncService.sync(container: container, userID: userID)
                lastError = nil
                lastSyncedAt = .now
                failuresInARow = 0
                succeeded = true
                // REFRESH THE PROFILE LIST THE UI IS ACTUALLY READING.
                //
                // `sync` applies to a private context; `ProfileStore.profiles` is a
                // cached array built by an earlier fetch, so a person added or
                // removed on another device stayed invisible here until something
                // happened to call reload — in practice, opening Family or
                // relaunching. The switcher and the assignee picker read this array,
                // so they could offer a profile that no longer exists.
                profiles?.reload(container.mainContext)

                // AND RESCHEDULE, because a pull can change WHEN reminders fire.
                //
                // A profile's `reminderMinutes` syncs, but reloading the store only
                // updates what the UI reads — the notifications already queued with
                // iOS still carry the old time. Foregrounding reschedules BEFORE it
                // syncs, so without this the other device kept the previous time
                // until some later foreground happened to run after the change had
                // landed. Pulled to-dos need it too: their dates are new here.
                let items = (try? container.mainContext.fetch(FetchDescriptor<ActionItem>())) ?? []
                ReminderScheduler.shared.rescheduleAll(for: items)

                // The server had more than one page — keep going rather than leave
                // the device holding a partial view of the account.
                if outcome.hasMore { needsAnotherPass = true }
            } catch SyncService.SyncError.accountChanged {
                // The user signed out or switched accounts while this was in the
                // air. Nothing was applied; just stop. Not an error to show.
                return false
            } catch SyncService.SyncError.unauthorized {
                // Session revoked — this device was signed in elsewhere. Both halves
                // must happen together: clearing the token without signing the
                // account out leaves the UI claiming to be signed in with nothing
                // behind it.
                SessionStore.clear()
                // Also drops the RevenueCat identity — otherwise this phone keeps
                // the departed user's Plus entitlement.
                await account.signOutAfterSessionEnded()
                signedOutRemotely = true
                return false
            } catch SyncService.SyncError.notConfigured, SyncService.SyncError.noSession {
                // No backend configured / not signed in yet: stay local, stay quiet.
                return false
            } catch {
                lastError = error.localizedDescription
                failuresInARow += 1
                return false    // don't spin on a failing server
            }
        } while needsAnotherPass
        return succeeded
    }

    // Everything on this device that is personal and account-scoped: the user's
    // to-dos AND the family profiles (other people's names). Reconciliation counts
    // both, because either one crossing accounts is the same privacy failure.
    //
    // `forAccount` is the account about to take ownership. An owner profile counts
    // only when it ISN'T this account's own — a freshly-created owner is just an
    // empty placeholder and shouldn't trigger a prompt, but an owner profile left
    // behind by a DIFFERENT account carries that person's name and must never be
    // adopted silently. That distinction is why the id is account-derived.
    // THROWS: this count decides whether the "these belong to another account"
    // prompt appears. A swallowed error would read as "this device is empty" and
    // skip the prompt entirely — the failure mode is a silent cross-account
    // upload, so it must be impossible to reach by accident.
    private func localPersonalDataCount(in context: ModelContext, forAccount userID: String) throws -> Int {
        let tasks = try context.fetchCount(
            FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample }))
        let canonicalOwner = Profile.ownerID(forAccount: userID)
        let people = try context.fetch(FetchDescriptor<Profile>())
            .filter { !$0.isOwner || ($0.id != canonicalOwner && !$0.name.isEmpty) }
            .count
        return tasks + people
    }
}
