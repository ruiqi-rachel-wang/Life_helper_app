//  DiscardableProfileTests.swift
//
//  A free account is allowed exactly ONE profile, and the user saw two — both
//  called "Unnamed".
//
//  Cause: signing into a different account demoted the device's old owner and
//  KEPT it. On a device whose owner had never been named, that left a nameless,
//  empty profile sitting in the switcher forever. The user never created it,
//  can't explain it, and on the free tier (cap 1) it consumes their only slot.
//  Verified against the Simulator's store — two ZPROFILE rows, both with an empty
//  name and zero to-dos between them.
//
//  Demoting is right when the profile is somebody. These tests pin the line
//  between "somebody" and "artifact": a profile is only discardable when it has
//  NO name AND NO to-dos. Either one alone makes it a person's, and it stays.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct DiscardableProfileTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func store() -> ProfileStore {
        ProfileStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    // The exact shape found on the device: a nameless, empty ex-owner.
    @Test func signingIntoAnotherAccountLeavesNoNamelessEmptyProfile() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "")           // never named — no display name yet
        try ctx.save()

        try s.bindOwner(to: "apple-user-B", in: ctx, previousAccountOverride: "apple-user-A")
        try ctx.save()

        #expect(s.profiles.count == 1, "a free account must end up with exactly one profile")
        #expect(s.profiles.filter(\.isOwner).count == 1)
        #expect(s.profiles.first?.id == Profile.ownerID(forAccount: "apple-user-B"))
    }

    // The other half: a leftover that IS someone must survive.
    @Test func aNamedPreviousOwnerIsKept() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Ana")
        try ctx.save()

        try s.bindOwner(to: "apple-user-B", in: ctx, previousAccountOverride: "apple-user-A")
        try ctx.save()

        #expect(s.profiles.count == 2)
        let ana = s.profiles.first { $0.name == "Ana" }
        #expect(ana != nil, "Ana's profile must not be deleted")
        #expect(ana?.isOwner == false, "she is no longer the account holder, but she still exists")
        #expect(ana?.id == owner.id)
    }

    @Test func anUnnamedProfileHoldingToDosIsKept() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "")
        let item = ActionItem(title: "Pay the gas bill", category: .utility)
        item.profileID = owner.id
        ctx.insert(item)
        try ctx.save()

        try s.bindOwner(to: "apple-user-B", in: ctx, previousAccountOverride: "apple-user-A")
        try ctx.save()

        #expect(s.profiles.count == 2, "it has no name, but it holds someone's to-dos")
        #expect(s.profiles.contains { $0.id == owner.id })
    }

    // Devices that already ran the old code carry the leftover on disk, so the
    // fix has to clean up as well as prevent.
    @Test func launchSweepsALeftoverFromAnEarlierBuild() throws {
        let ctx = try context()
        let s = store()
        let real = s.ensureOwnerProfile(ctx, name: "Rachel")
        let leftover = Profile(name: "", colorIndex: 1, isOwner: false)
        ctx.insert(leftover)
        try ctx.save()
        s.reload(ctx)
        #expect(s.profiles.count == 2)

        s.ensureOwnerProfile(ctx, name: "Rachel")     // next launch
        try ctx.save()

        #expect(s.profiles.count == 1)
        #expect(s.profiles.first?.id == real.id)

        // The removal has to reach the family's other devices, or they pull it back.
        let tombstones = try ctx.fetch(FetchDescriptor<ProfileTombstone>())
        #expect(tombstones.contains { $0.id == leftover.id })
    }

    @Test func theSweepNeverRemovesTheLastProfile() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "")           // nameless, empty — but it's all there is
        try ctx.save()

        s.ensureOwnerProfile(ctx, name: "")
        try ctx.save()

        #expect(s.profiles.count == 1)
    }
}
