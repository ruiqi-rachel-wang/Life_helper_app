//  OwnerIdentityTests.swift
//
//  The owner profile is created on every install, BEFORE anyone signs in. When its
//  id was random, that had two bad consequences:
//
//    • every device signing into the same account pushed its own "owner", so a
//      family of three ended up with three owners;
//    • an owner profile left behind by account A could be pushed into account B
//      under A's name.
//
//  Deriving the id from the Apple user id fixes both: every device computes the
//  SAME id for the same account, and a different account computes a different one.
//

// NOTE: every bindOwner call here passes `previousAccountOverride` explicitly.
// LocalDataOwner reads UserDefaults.standard, other suites write it, and Swift
// Testing runs suites in parallel — so leaving it implicit made these tests
// depend on whatever else happened to be running.
import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct OwnerIdentityTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func store() -> ProfileStore {
        ProfileStore(defaults: UserDefaults(suiteName: "owner.\(UUID().uuidString)")!)
    }

    // MARK: the derived id

    @Test func ownerIDIsStableForAnAccountAndDiffersBetweenAccounts() {
        let a1 = Profile.ownerID(forAccount: "apple-sub-A")
        let a2 = Profile.ownerID(forAccount: "apple-sub-A")
        let b = Profile.ownerID(forAccount: "apple-sub-B")
        #expect(a1 == a2)      // every device agrees
        #expect(a1 != b)       // B can never collide with A
    }

    // MARK: binding on sign-in

    // Two devices, two random owner ids, same account → after binding they agree,
    // so the account ends up with ONE owner instead of one per device.
    @Test func twoDevicesConvergeOnTheSameOwnerID() throws {
        let expected = Profile.ownerID(forAccount: "apple-sub-A")

        for _ in 0..<2 {
            let ctx = try context()
            let s = store()
            s.ensureOwnerProfile(ctx, name: "Jing")     // random id, pre-sign-in
            try ctx.save()

            try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A")
            try ctx.save()

            let owners = try ctx.fetch(FetchDescriptor<Profile>()).filter(\.isOwner)
            #expect(owners.count == 1)
            #expect(owners.first?.id == expected)
        }
    }

    // Re-keying must carry the owner's to-dos with it, or they'd be orphaned —
    // pointing at an id no profile has anymore.
    @Test func rekeyingTheOwnerMovesTheirItemsToo() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mine = ActionItem(title: "my bill", category: .utility)
        mine.profileID = owner.id
        ctx.insert(mine)
        try ctx.save()

        try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A")
        try ctx.save()

        let canonical = Profile.ownerID(forAccount: "apple-sub-A")
        #expect(mine.profileID == canonical)
        // Touched, so the re-pointing actually reaches the other devices.
        #expect(abs(mine.updatedAt.timeIntervalSinceNow) < 5)
    }

    // Account A's leftover owner must NOT become account B's owner — not even by
    // having its id changed.
    //
    // The earlier version of this test only checked that SOME profile named "Ana"
    // still existed, which passed trivially: re-keying moved Ana's profile onto
    // B's canonical id, so B's account holder was literally called Ana. One
    // person's name silently became another person's owner. A's profile must be
    // DEMOTED and left under its own id.
    @Test func anotherAccountsOwnerIsDemotedAndItsNameNeverTransfers() throws {
        let ctx = try context()
        let s = store()
        // Device was signed into account A.
        s.ensureOwnerProfile(ctx, name: "Ana")
        try ctx.save()
        try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A")
        try ctx.save()
        let ownerOfA = Profile.ownerID(forAccount: "apple-sub-A")

        // Now account B signs in on the same phone (consent already given).
        try s.bindOwner(to: "apple-sub-B", name: "Bea", in: ctx,
                        previousAccountOverride: "apple-sub-A")
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Profile>())
        let owners = all.filter(\.isOwner)
        #expect(owners.count == 1)
        #expect(owners.first?.id == Profile.ownerID(forAccount: "apple-sub-B"))
        // THE POINT: B's owner is not wearing A's name.
        #expect(owners.first?.name != "Ana")
        // And A's profile survives, demoted, under its own id.
        let ana = all.first { $0.id == ownerOfA }
        #expect(ana != nil)
        #expect(ana?.isOwner == false)
        #expect(ana?.name == "Ana")
    }

    // THE MIGRATION HAS TO BE PUSHABLE. Re-keying the owner locally is only half
    // the job: without a tombstone for the old random id, the server keeps that
    // profile forever. A free account then looks like it has TWO profiles and the
    // server rejects the canonical owner with a 409 profile_limit — the migration
    // can never complete — and other devices keep pulling the ghost owner back.
    @Test func rekeyingTombstonesTheOldOwnerSoTheServerDropsIt() throws {
        let ctx = try context()
        let s = store()
        let original = s.ensureOwnerProfile(ctx, name: "Jing")
        let randomID = original.id
        try ctx.save()

        try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A")
        try ctx.save()

        let stones = try ctx.fetch(FetchDescriptor<ProfileTombstone>())
        #expect(stones.contains { $0.id == randomID })
        // And exactly one profile remains locally, under the canonical id.
        let all = try ctx.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 1)
        #expect(all.first?.id == Profile.ownerID(forAccount: "apple-sub-A"))
    }

    // Another device already migrated and its canonical owner arrived in a pull.
    // Binding must ADOPT that one rather than insert a second profile under an id
    // that already exists.
    @Test func bindingAdoptsACanonicalOwnerThatAlreadyArrived() throws {
        let ctx = try context()
        let s = store()
        let local = s.ensureOwnerProfile(ctx, name: "Jing")
        let randomID = local.id

        // Pulled from the account, already migrated elsewhere.
        let canonical = Profile.ownerID(forAccount: "apple-sub-A")
        let fromServer = Profile(name: "Jing", colorIndex: 0, isOwner: false, id: canonical)
        ctx.insert(fromServer)
        try ctx.save()

        try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A")
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 1)                       // no duplicate inserted
        #expect(all.first?.id == canonical)
        #expect(all.first?.isOwner == true)
        let stones = try ctx.fetch(FetchDescriptor<ProfileTombstone>())
        #expect(stones.contains { $0.id == randomID })
    }

    // Duplicate resolution must prefer the CANONICAL id, not merely the oldest.
    // Picking the oldest could demote the account-derived owner in favour of a
    // legacy random one, which the next migration would re-promote — flip-flopping
    // forever and re-syncing on every pass.
    @MainActor
    @Test func duplicateResolutionPrefersTheCanonicalOwner() throws {
        let ctx = try context()
        let canonical = Profile.ownerID(forAccount: "apple-sub-A")

        // The legacy random owner is OLDER, so "oldest wins" would pick it.
        let legacy = Profile(name: "Jing (old device)", colorIndex: 0, isOwner: true)
        legacy.createdAt = Date(timeIntervalSince1970: 1000)
        let canonicalProfile = Profile(name: "Jing", colorIndex: 0, isOwner: true, id: canonical)
        canonicalProfile.createdAt = Date(timeIntervalSince1970: 9000)

        try SyncService.applyProfileChanges(
            [ProfileDTO(legacy), ProfileDTO(canonicalProfile)],
            canonicalOwner: canonical, in: ctx)
        try ctx.save()

        let owners = try ctx.fetch(FetchDescriptor<Profile>()).filter(\.isOwner)
        #expect(owners.count == 1)
        #expect(owners.first?.id == canonical)
    }

    // An empty or repaired store can legitimately have no profile yet. Treating
    // that as "nothing to bind" leaves the account with no owner, so a
    // successful-but-empty read must create the canonical owner.
    @Test func bindingRecreatesTheOwnerWhenEveryProfileWasDeleted() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        // Reproduce an empty profile store.
        for p in try ctx.fetch(FetchDescriptor<Profile>()) { ctx.delete(p) }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).isEmpty)

        try s.bindOwner(to: "apple-sub-A", name: "Jing", in: ctx, previousAccountOverride: "apple-sub-A")
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 1)
        let owner = try #require(all.first)
        #expect(owner.isOwner)
        #expect(owner.id == Profile.ownerID(forAccount: "apple-sub-A"))
        #expect(owner.name == "Jing")            // not blank
        #expect(s.activeProfileID == owner.id)   // and it's the active profile
    }

    // NOTE: there is deliberately no test for "bindOwner throws when the store
    // can't be read". SwiftData gives no supported way to make a fetch fail from a
    // test, and the obvious fake (fetching Profile from a container that doesn't
    // declare it) does NOT throw. A test asserting that would have been theatre —
    // the same hollow-coverage problem this file has been bitten by before. The
    // throwing read is verified by inspection: `bindOwner` calls `reloadThrowing`,
    // which has no `try?` in it.

    @Test func bindingIsIdempotent() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        for _ in 0..<3 { try s.bindOwner(to: "apple-sub-A", in: ctx, previousAccountOverride: "apple-sub-A"); try ctx.save() }

        let owners = try ctx.fetch(FetchDescriptor<Profile>()).filter(\.isOwner)
        #expect(owners.count == 1)
        #expect(owners.first?.id == Profile.ownerID(forAccount: "apple-sub-A"))
    }
}
