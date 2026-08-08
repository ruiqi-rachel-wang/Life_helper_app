//  LocalDataOwner.swift
//
//  Which account the to-dos currently on this device belong to.
//
//  WHY THIS EXISTS: local items are stored in one SwiftData store with no account
//  column, and sign-out deliberately leaves them alone ("your data survives
//  sign-out"). Without a marker, the app cannot tell "these are MY tasks, waiting
//  for me to sign back in" from "these are the PREVIOUS person's tasks". The two
//  need opposite handling, and getting it wrong is a privacy failure, not a bug:
//
//      user A signs out → user B signs in with a brand-new Apple account →
//      B's account has no server data → the device seeds it from local →
//      A's tasks are now in B's cloud backup.
//
//  So: the marker is claimed when an account takes ownership of what's on the
//  device, and it deliberately SURVIVES sign-out. A mismatch on the next sign-in
//  means the local items belong to someone else and must never be pushed without
//  the person explicitly saying so (see SyncCoordinator.afterSignIn).
//
//  nil = unclaimed (guest data from before any sign-in). That case is safe to seed
//  into a new account, and is the documented "your existing to-dos come with you
//  when you create an account" behaviour.
//

import Foundation

enum LocalDataOwner {
    private static let key = "tadah.localData.ownerUserID"

    static func current(_ d: UserDefaults = .standard) -> String? {
        d.string(forKey: key)
    }

    // This account now owns what's on the device. Called once the reconciliation
    // question (if any) has been answered, never before.
    static func claim(_ userID: String, _ d: UserDefaults = .standard) {
        d.set(userID, forKey: key)
    }

    // Back to unclaimed. Used when the local items are erased along with the
    // account, so the next person starts genuinely fresh.
    static func release(_ d: UserDefaults = .standard) {
        d.removeObject(forKey: key)
    }

    // True when the device holds items that a DIFFERENT account claimed.
    static func belongsToSomeoneElse(than userID: String, _ d: UserDefaults = .standard) -> Bool {
        guard let owner = current(d) else { return false }   // unclaimed guest data
        return owner != userID
    }
}
