//  LocalDataOwnerTests.swift
//
//  The privacy boundary between two people who use the same phone.
//
//  Local to-dos live in one store with no account column, and signing out
//  deliberately leaves them there. Without an owner marker the app cannot tell
//  "my tasks, waiting for me to sign back in" from "the previous person's tasks",
//  and it used to resolve that ambiguity the worst possible way: any account with
//  no server data got seeded from whatever was on the device. So user A signs out,
//  user B signs in with a brand-new Apple id, and A's to-dos become B's cloud
//  backup.
//

import Testing
import Foundation
@testable import Tadah

struct LocalDataOwnerTests {

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "owner-tests-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    // Guest data — nobody has claimed it — is safe to carry into a first account.
    // This is the documented "your existing to-dos come with you" behaviour.
    @Test func unclaimedDataBelongsToNobody() {
        let d = freshDefaults()
        #expect(LocalDataOwner.current(d) == nil)
        #expect(!LocalDataOwner.belongsToSomeoneElse(than: "userA", d))
    }

    @Test func ownerRecognisesItsOwnData() {
        let d = freshDefaults()
        LocalDataOwner.claim("userA", d)
        #expect(!LocalDataOwner.belongsToSomeoneElse(than: "userA", d))
    }

    // THE ONE THAT MATTERS: after A signs out, the marker must still say A, so B's
    // sign-in is recognised as a different person and nothing is auto-uploaded.
    @Test func differentAccountIsDetectedAfterSignOut() {
        let d = freshDefaults()
        LocalDataOwner.claim("userA", d)
        // Signing out intentionally leaves both the items AND the claim in place.
        #expect(LocalDataOwner.belongsToSomeoneElse(than: "userB", d))
    }

    @Test func claimTransfersOnlyWhenExplicitlyMoved() {
        let d = freshDefaults()
        LocalDataOwner.claim("userA", d)
        LocalDataOwner.claim("userB", d)     // the user chose "move them to this account"
        #expect(!LocalDataOwner.belongsToSomeoneElse(than: "userB", d))
        #expect(LocalDataOwner.belongsToSomeoneElse(than: "userA", d))
    }

    // Releasing is only for when the items are erased at the same time — it makes
    // whatever is left look like guest data.
    @Test func releaseReturnsDataToUnclaimed() {
        let d = freshDefaults()
        LocalDataOwner.claim("userA", d)
        LocalDataOwner.releaseAfterErasingItems(d)
        #expect(LocalDataOwner.current(d) == nil)
        #expect(!LocalDataOwner.belongsToSomeoneElse(than: "userB", d))
    }

    // DELETING AN ACCOUNT MUST NOT RELEASE THE CLAIM. Deletion deliberately leaves
    // the to-dos on the phone, so releasing would mark real personal data as
    // unclaimed guest data — and the next account to sign in would upload it
    // automatically, which is the leak this whole file exists to prevent.
    //
    // Keeping the claim also gets the friendly case right: the SAME person signing
    // back in (their Apple id is unchanged) is recognised and simply merges.
    @Test func deletedAccountKeepsItsClaimSoLeftoverItemsCannotBeAdopted() {
        let d = freshDefaults()
        LocalDataOwner.claim("userA", d)
        // …account deleted on the server; items stay on the device; no release call.
        #expect(LocalDataOwner.belongsToSomeoneElse(than: "userB", d))
        #expect(!LocalDataOwner.belongsToSomeoneElse(than: "userA", d))
    }
}
