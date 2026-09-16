//  CallCenter.swift
//
//  Every Tadah call goes through here, from "Call now" to the answer on the
//  to-do. It belongs to the APP, not to a screen.
//
//  WHY. A call used to belong to the Review screen's card. Leaving Review
//  cancelled the watch, so the answer waited for the next time the app came to
//  the foreground. Leaving in the first second or two was worse: it cancelled
//  the request that PLACES the call, so a call CALL-E had already dialled left
//  no trace on the phone at all. Now "Call now" hands the call to this object
//  and takes the user to the to-do, which shows the same call live. No screen
//  can cancel anything here.
//
//  ⚠️ NOTHING HERE REDIALS. `place` makes exactly one request per tap (plus the
//  one Plus re-check described there, which the Worker refuses before charging
//  or dialling). Everything after that only READS how a call we already placed
//  is going. A paid phone line that redials on its own is the one bug this
//  feature must never have.
//

import Foundation
import UIKit

@MainActor @Observable
final class CallCenter {
    static let shared = CallCenter()

    enum Phase: Equatable {
        /// "Call now" was tapped. The answer isn't in yet.
        case calling(since: Date, business: String?, dryRun: Bool)
        case checking
        case finished(CallRecord)
        /// The Worker refused to place it. Nothing was dialled.
        case refused(Refusal)
    }

    struct Refusal: Equatable {
        let message: String
        let error: ActionsService.ActionError?
        /// What the user last sent, so "Try again" on the to-do reopens the
        /// confirm page as they left it instead of being a dead end.
        let retry: Retry
    }

    struct Retry: Equatable, Identifiable {
        let id = UUID()
        let offer: CallOffer
        let phone: String
        let goal: String
    }

    /// Set once at launch (TadahApp). Re-files a subscription under the account
    /// when the Worker says "Plus required" but the phone says Plus — see `send`.
    @ObservationIgnored var recoverPlus: (@MainActor () async -> Bool)?

    /// Calls this session knows about, by to-do. Observed, so the to-do page
    /// changes the moment its call does.
    private var phases: [UUID: Phase] = [:]
    private var owners: [UUID: String] = [:]
    /// Action ids with a poller running, so two can never watch one call.
    @ObservationIgnored private var watching: Set<String> = []

    private init() {}

    /// What the to-do page shows about a call, or nil when there never was one.
    func phase(for itemID: UUID) -> Phase? {
        if let phase = phases[itemID], owners[itemID] == SessionStore.userID { return phase }
        // Not seen this session: fall back to what's on disk.
        if let call = PendingCall.inFlight(for: itemID), call.belongs(to: SessionStore.userID) {
            if call.uncertain == true { return .checking }
            return .calling(since: call.startedAt ?? .now, business: call.business, dryRun: false)
        }
        return CallHistory.record(for: itemID).map(Phase.finished)
    }

    // ── Placing ─────────────────────────────────────────────────────────────

    /// "Call now". The to-do must already be saved: the answer lands on it.
    func place(offer: CallOffer, phone: String, goal: String, mayAgreeTo: String,
               shareAccount: Bool, name: String, language: String, itemID: UUID) {
        if case .checking = phase(for: itemID) { return }
        if case .calling = phase(for: itemID) { return }   // one tap, one call

        var request = Self.request(offer: offer, phone: phone, goal: goal, mayAgreeTo: mayAgreeTo,
                                   shareAccount: shareAccount, name: name, language: language,
                                   itemID: itemID)
        request.requestID = UUID().uuidString
        request.business = offer.business
        let retry = Retry(offer: offer, phone: phone, goal: goal)
        let startedAt = Date()
        // Captured once. Every later step checks it is still this account: a
        // sign-out and a different sign-in can happen during any await.
        let owner = SessionStore.userID
        owners[itemID] = owner
        let pending = PendingCall.InFlight(actionID: request.requestID!, business: offer.business,
                                            startedAt: startedAt, owner: owner, uncertain: true)
        // Persist BEFORE the network request: its reply is not required to find it.
        PendingCall.remember(pending, for: itemID)
        phases[itemID] = .calling(since: startedAt, business: offer.business, dryRun: false)
        // Counted when the person says yes, whether or not the call then goes
        // through: this is the intent the funnel measures.
        Metrics.record(.actionAccepted, itemID: itemID)

        // The user is usually leaving Review as this starts, and may leave the
        // app too. Ask iOS for time to finish this ONE request: if its answer is
        // lost, the phone never learns which call to watch.
        let backgroundTime = BackgroundTime(named: "Place a Tadah call")
        Task {
            defer { backgroundTime.end() }
            do {
                let placed = try await send(request, owner: owner)
                guard PendingCall.inFlight(for: itemID)?.actionID == pending.actionID else { return }
                let call = PendingCall.InFlight(actionID: placed.actionID, business: offer.business,
                                                startedAt: startedAt, owner: owner, uncertain: placed.status == "uncertain")
                // Remembered even if the account changed meanwhile: the call is
                // real and belongs to `owner`, whose next sign-in picks it up.
                PendingCall.remember(call, for: itemID)
                guard call.belongs(to: SessionStore.userID) else { return }
                phases[itemID] = placed.status == "uncertain" ? .checking : .calling(since: startedAt, business: offer.business, dryRun: placed.dryRun)
                watch(call, for: itemID)
            } catch {
                guard PendingCall.inFlight(for: itemID)?.actionID == pending.actionID else { return }
                let actionError = error as? ActionsService.ActionError
                guard Self.isDefiniteRefusal(error) else {
                    if pending.belongs(to: SessionStore.userID) {
                        phases[itemID] = .checking
                        watch(pending, for: itemID)
                    }
                    return
                }
                PendingCall.forget(itemID)
                guard !Task.isCancelled, SessionStore.userID == owner else { return }
                phases[itemID] = .refused(Refusal(
                    message: actionError?.errorDescription
                        ?? String(localized: "Tadah couldn't place the call. Please try again."),
                    error: actionError,
                    retry: retry))
            }
        }
    }

    /// What goes to the Worker. The account number is added ONLY when the user
    /// switched it on; nothing about the document is sent silently.
    static func request(offer: CallOffer, phone: String, goal: String, mayAgreeTo: String,
                        shareAccount: Bool, name: String, language: String,
                        itemID: UUID) -> ActionsService.CallRequest {
        // Switch off = the account number is not sent, even if it is still in
        // the question (a script that named it, or the user typing it in).
        var goalText = shareAccount ? goal : CallOffer.removingReference(offer.accountNumber, from: goal)
        if shareAccount, let account = offer.accountNumber, !account.isEmpty {
            let label = offer.accountLabel ?? String(localized: "account")
            goalText += "\n\n" + String(localized: "My \(label) number is \(account).")
        }
        // Whom the call is to, or the agent opens every call not knowing what
        // business it has reached. Plain English, not localized: the agent reads
        // it, the user never sees it.
        if let business = offer.business, !business.isEmpty {
            goalText = "You are calling \(business).\n\n" + goalText
        }
        return ActionsService.CallRequest(phone: phone, goal: goalText, mayAgreeTo: mayAgreeTo,
                                          name: name, itemID: itemID.uuidString, language: language)
    }

    /// Place the call, and don't believe a "Plus required" the phone disagrees
    /// with until it has checked.
    ///
    /// The Worker asks RevenueCat about the ACCOUNT's id and fails closed; this
    /// device reads the receipt in front of it. When a `logIn` never landed, the
    /// purchase sits under an id the Worker never asks about, and a subscriber is
    /// told to buy what they already own. `recoverPlus` re-files it and we ask
    /// once more. The Worker refuses Plus BEFORE it charges or dials, so the
    /// second request can't be a second call. ONE retry, never a loop: if the
    /// recovery finds no subscription, the original refusal stands, and it's true.
    private func send(_ request: ActionsService.CallRequest, owner: String?) async throws -> ActionsService.Placed {
        guard SessionStore.userID == owner else { throw ActionsService.ActionError.noSession }
        do {
            return try await ActionsService.placeCall(request)
        } catch let error as ActionsService.ActionError where error.needsPlus {
            guard let recoverPlus, SessionStore.userID == owner, await recoverPlus() else { throw error }
            // The recovery awaited too. Never send one account's confirmed call
            // under a different account's session.
            guard SessionStore.userID == owner else { throw error }
            return try await ActionsService.placeCall(request)
        }
    }

    // ── Watching ────────────────────────────────────────────────────────────

    /// Pick up every call this phone started and hasn't seen the end of. Runs at
    /// launch and whenever the app comes back. Safe to call as often as you
    /// like: a call already being watched is skipped.
    func resumeAll() {
        let signedIn = SessionStore.userID
        for (itemID, call) in PendingCall.all where call.belongs(to: signedIn) {
            owners[itemID] = signedIn
            if phases[itemID] == nil {
                phases[itemID] = call.uncertain == true ? .checking : .calling(since: call.startedAt ?? .now, business: call.business, dryRun: false)
            }
            watch(call, for: itemID)
        }
    }

    private func watch(_ call: PendingCall.InFlight, for itemID: UUID) {
        guard watching.insert(call.actionID).inserted else { return }
        let startedAt = call.startedAt ?? .now
        Task {
            defer { watching.remove(call.actionID) }
            while true {
                // Another account signed in: stop, and keep the breadcrumb for
                // the owner. Polling under the new session would get a 404 and
                // throw the owner's call away.
                guard call.belongs(to: SessionStore.userID), PendingCall.inFlight(for: itemID)?.actionID == call.actionID else { return }
                // ASK FIRST, THEN WAIT. A watch that slept through the app being
                // in the background wakes up asking, so coming back to the app
                // always gets a fresh answer.
                do {
                    let status = try await ActionsService.status(of: call.actionID)
                    guard call.belongs(to: SessionStore.userID), PendingCall.inFlight(for: itemID)?.actionID == call.actionID else { return }
                    if status.isFinished {
                        finish(status, call: call, itemID: itemID)
                        return
                    }
                    phases[itemID] = status.status == "uncertain" ? .checking : .calling(since: startedAt, business: call.business, dryRun: false)
                } catch ActionsService.ActionError.server(404) {
                    // A lost POST may still be arriving at the server. Keep its
                    // durable ID and never turn a missing read into a new call.
                    guard call.belongs(to: SessionStore.userID), PendingCall.inFlight(for: itemID)?.actionID == call.actionID else { return }
                    phases[itemID] = .checking
                } catch let error as ActionsService.ActionError
                            where error == .noSession || error == .notConfigured {
                    // Signed out. The breadcrumb stays, so signing back in picks
                    // the call up again.
                    return
                } catch {
                    // ⚠️ A FAILED POLL IS NOT A FAILED CALL. The call was placed
                    // and paid for; a dropped request (a lift, a flaky carrier)
                    // only means we can't see it yet. Ask again next tick.
                    #if DEBUG
                    print("[Calls] poll missed, retrying: \(error)")
                    #endif
                }
                guard let delay = Self.pollDelay(sinceStart: Date().timeIntervalSince(startedAt)) else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    static func isDefiniteRefusal(_ error: Error) -> Bool {
        guard let error = error as? ActionsService.ActionError else { return false }
        switch error {
        case .decode, .providerFailed: return false
        case .server(let status): return (400..<500).contains(status)
        default: return true
        }
    }

    /// A synced to-do can find its answer without this device placing the call.
    func refresh(itemID: UUID) async {
        guard let owner = SessionStore.userID else { return }
        do {
            let status = try await ActionsService.status(for: itemID)
            guard !Task.isCancelled, SessionStore.userID == owner else { return }
            // A newer local confirmation must not be replaced by an older call.
            if let pending = PendingCall.inFlight(for: itemID), pending.actionID != status.actionID { return }
            // ⚠️ A REJECTED CALL NEVER HAPPENED. CALL-E refused it before dialling
            // (a clarifying question, a refused number). Saving it as a finished
            // call showed "Nobody could be reached. Nothing was agreed." on the
            // to-do, which is false: nobody was ever rung. Show the offer again.
            if status.status == "rejected" {
                PendingCall.forget(itemID)
                if case .refused = phases[itemID] {} else { phases[itemID] = nil }
                return
            }
            owners[itemID] = owner
            let call = PendingCall.InFlight(actionID: status.actionID, business: status.business,
                startedAt: status.createdAt.flatMap { try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0) },
                owner: owner, uncertain: status.status == "uncertain")
            if status.isFinished {
                CallHistory.save(CallRecord(status, business: status.business), for: itemID)
                phases[itemID] = .finished(CallRecord(status, business: status.business))
                PendingCall.forget(itemID)
            } else {
                PendingCall.remember(call, for: itemID)
                phases[itemID] = call.uncertain == true ? .checking : .calling(since: call.startedAt ?? .now, business: call.business, dryRun: false)
                watch(call, for: itemID)
            }
        } catch { /* A missing or offline read does not alter a local call. */ }
    }

    /// Seconds until the next status check, or nil to stop for now.
    ///
    /// Every 5 seconds for the first 10 minutes, when the answer usually lands
    /// and someone may be looking at the to-do. Then every 30 seconds. After two
    /// hours, stop: the call is still on record, and the next launch or return
    /// to the app asks again. There is no hard deadline before that, because a
    /// watch that gives up while the user is looking at the to-do is exactly the
    /// bug this file replaced.
    nonisolated static func pollDelay(sinceStart age: TimeInterval) -> TimeInterval? {
        if age < 10 * 60 { return 5 }
        if age < 2 * 60 * 60 { return 30 }
        return nil
    }

    private func finish(_ status: ActionsService.ActionStatus, call: PendingCall.InFlight, itemID: UUID) {
        // Refused before dialling: nothing to record as a call. See `refresh`.
        guard status.status != "rejected" else {
            PendingCall.forget(itemID)
            if case .refused = phases[itemID] {} else { phases[itemID] = nil }
            return
        }
        let record = CallRecord(status, business: call.business)
        CallHistory.save(record, for: itemID)
        PendingCall.forget(itemID)
        phases[itemID] = .finished(record)
        // The ONE place a call is counted as completed. Review and the old
        // watcher both used to record it, and a call watched by both counted twice.
        if !record.didFail { Metrics.record(.actionCompleted, itemID: itemID) }
    }
}

/// Extra running time from iOS for one piece of work, ended exactly once
/// whether the work finishes or iOS runs out of patience first.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(named name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
