//  ReconciliationGate.swift
//
//  A DURABLE "this account may not sync yet" marker.
//
//  WHY IT CAN'T LIVE IN MEMORY. The account and the session are written to disk
//  the moment the Worker issues them, so anything that guards syncing has to be at
//  least as durable as they are. Otherwise:
//
//      account A's data is on the phone
//      → B signs in, gets the "these belong to another account" question
//      → the app is killed before it's answered
//      → relaunch: a brand-new coordinator, no pending question
//      → startup calls syncNow, every guard passes
//      → A's to-dos upload into B's account
//
//  WHY IT'S RAISED BEFORE THE SESSION IS SAVED. There is a second, narrower window
//  with the same ending: AuthService persists the Keychain session, and only then
//  does the caller reach the code that raises the question. Killing the app in
//  between left an authenticated, persisted session with nothing blocking it. So
//  the block goes down FIRST — `.setupIncomplete` — and is only ever replaced by a
//  real question or cleared once setup has actually finished.
//
//  The block is scoped to the SESSION USER, so a question raised for B can never
//  silently apply to someone else, and it is cleared only as the LAST durable step
//  of a completed reconciliation.
//

import Foundation

enum ReconciliationGate {
    private static func key(_ userID: String) -> String {
        "tadah.reconciliationPending.\(userID)"
    }

    enum Reason: Equatable {
        // A session exists but sign-in setup never finished (crash, kill, error).
        // There is no safe way to resume it, so the session is given back.
        case setupIncomplete
        // A question is on screen and unanswered. Carries what it asked, so the
        // prompt can be rebuilt verbatim after a relaunch.
        case question(localCount: Int)
    }

    static func block(_ reason: Reason, for userID: String, _ d: UserDefaults = .standard) {
        switch reason {
        case .setupIncomplete:
            d.set(["reason": "setupIncomplete"], forKey: key(userID))
        case .question(let localCount):
            d.set(["reason": "question",
                   "localCount": localCount],
                  forKey: key(userID))
        }
    }

    static func reason(for userID: String, _ d: UserDefaults = .standard) -> Reason? {
        guard let raw = d.dictionary(forKey: key(userID)) else { return nil }
        switch raw["reason"] as? String {
        case "question":
            return .question(localCount: raw["localCount"] as? Int ?? 0)
        case "setupIncomplete":
            return .setupIncomplete
        default:
            // Unrecognised shape — treat as blocked. Failing closed is the whole
            // point of this file.
            return .setupIncomplete
        }
    }

    static func isBlocked(for userID: String, _ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: key(userID)) != nil
    }

    // ONLY as the final durable step, once every safety prerequisite (owner claim,
    // watermark/cursor state, the store save) is already committed. Clearing this
    // any earlier re-opens the exact window it exists to close: a crash in between
    // would relaunch unblocked, with half-applied sync state.
    static func clear(for userID: String, _ d: UserDefaults = .standard) {
        d.removeObject(forKey: key(userID))
    }
}
