//  ProfileTests.swift
//
//  Phase A of family sharing: profiles on the device. The risky parts are the
//  one-time backfill (existing testers must not lose sight of their to-dos) and
//  the per-tier cap, so those get the most attention.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct ProfileTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func store() -> ProfileStore {
        ProfileStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    // MARK: owner + backfill

    @Test func ensureOwnerCreatesExactlyOneOwnerAndIsIdempotent() throws {
        let ctx = try context()
        let s = store()
        let first = s.ensureOwnerProfile(ctx, name: "Jing")
        let second = s.ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        #expect(first.id == second.id)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(first.isOwner)
        #expect(s.profiles.count == 1)
    }

    // The upgrade path: a tester's existing to-dos have no profile and must all
    // land on the owner, or they'd vanish from the Inbox after updating.
    @Test func backfillAdoptsPreProfileItemsOntoTheOwner() throws {
        let ctx = try context()
        for i in 0..<3 { ctx.insert(ActionItem(title: "old \(i)", category: .utility)) }
        let example = ActionItem(title: "tutorial", category: .other)
        example.isExample = true
        ctx.insert(example)
        try ctx.save()

        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(all.allSatisfy { $0.profileID == owner.id })   // examples included
        #expect(all.count == 4)
    }

    // MARK: caps

    @Test func freeAccountCannotAddASecondProfile() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Jing")

        #expect(throws: ProfileStore.ProfileError.capReached(1)) {
            try s.add(name: "Mom", plus: false, in: ctx)
        }
        #expect(s.blockedReason(plus: false) != nil)
    }

    @Test func plusAllowsEightThenStops() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Jing")
        for i in 1..<ProfileStore.plusMax {
            _ = try s.add(name: "Member \(i)", plus: true, in: ctx)
        }
        #expect(s.profiles.count == ProfileStore.plusMax)
        #expect(throws: ProfileStore.ProfileError.capReached(8)) {
            try s.add(name: "One too many", plus: true, in: ctx)
        }
    }

    // MARK: switching + deletion

    @Test func ownerIsActiveByDefaultAndSwitchingSticks() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)

        #expect(s.active?.id == owner.id)      // defaults to the owner
        s.setActive(mom.id)
        #expect(s.active?.id == mom.id)
        #expect(s.activeProfileID == mom.id)
    }

    @Test func deletingAProfileTakesItsItemsAndFallsBackToOwner() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)

        let mine = ActionItem(title: "my bill", category: .utility)
        mine.profileID = owner.id
        let hers = ActionItem(title: "mom's bill", category: .utility)
        hers.profileID = mom.id
        ctx.insert(mine); ctx.insert(hers)
        try ctx.save()

        s.setActive(mom.id)
        try s.delete(mom, in: ctx)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "my bill")
        // Her deletion propagates to the family's other devices.
        #expect(try ctx.fetch(FetchDescriptor<TaskTombstone>()).count == 1)
        #expect(s.active?.id == owner.id)      // active fell back
    }

    @Test func ownerCannotBeDeleted() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        #expect(throws: ProfileStore.ProfileError.cannotDeleteOwner) {
            try s.delete(owner, in: ctx)
        }
    }

    // MARK: per-profile task cap

    @Test func taskLimitCountsPerProfileNotAccountWide() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)

        for i in 0..<5 {
            let item = ActionItem(title: "mine \(i)", category: .utility)
            item.profileID = owner.id
            ctx.insert(item)
        }
        try ctx.save()

        #expect(TaskLimit.count(ctx, profileID: owner.id) == 5)
        #expect(TaskLimit.count(ctx, profileID: mom.id) == 0)   // Mom's list is her own
        // Mom has all 100 of her Plus allowance despite the owner's 5.
        #expect(TaskLimit.remaining(ctx, plus: true, profileID: mom.id) == TaskLimit.maxPlus)
    }

    // MARK: serialization

    @Test func taskDTOCarriesProfileSoBackupsKeepIt() {
        let item = ActionItem(title: "Mom's bill", category: .utility)
        let pid = UUID()
        item.profileID = pid
        let rebuilt = TaskDTO(item).makeItem()
        #expect(rebuilt.profileID == pid)
    }

    @Test func recurringSpawnStaysWithTheSameProfile() {
        let item = ActionItem(title: "Rent", category: .housing,
                              dueDate: Date(timeIntervalSince1970: 1_800_000_000),
                              recurrence: .monthly)
        let pid = UUID()
        item.profileID = pid
        let next = item.makeNextOccurrence()
        #expect(next?.profileID == pid)
    }
}
