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
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
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

    // THE BACKFILL MUST BE ONE-TIME. `profileID == nil` has two meanings that look
    // identical in the data: "saved before profiles existed" (backfill it onto the
    // owner) and "filed under Everyone" (a shared family errand — leave it alone).
    // Only the order of events tells them apart, so the backfill runs once and then
    // never again.
    //
    // When it ran on every launch, every Everyone task was silently reassigned to
    // the owner, so choosing Everyone never survived a relaunch.
    @Test func everyoneTasksSurviveRelaunchAfterTheBackfillHasRun() throws {
        let ctx = try context()
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!

        // First launch after upgrading: an old item gets adopted onto the owner.
        ctx.insert(ActionItem(title: "from before profiles", category: .utility))
        try ctx.save()
        let owner = ProfileStore(defaults: defaults).ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        // Now the user files a NEW to-do under Everyone (profileID stays nil).
        let shared = ActionItem(title: "family errand", category: .other)
        ctx.insert(shared)
        try ctx.save()

        // Relaunch — same defaults, so the backfill flag persists.
        ProfileStore(defaults: defaults).ensureOwnerProfile(ctx, name: "Jing")
        try ctx.save()

        #expect(shared.profileID == nil)          // still Everyone's
        let old = try #require(try ctx.fetch(FetchDescriptor<ActionItem>())
            .first { $0.title == "from before profiles" })
        #expect(old.profileID == owner.id)        // the one-time adoption held
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

        #expect(s.me?.id == owner.id)      // defaults to the owner
        s.setActive(mom.id)
        #expect(s.me?.id == mom.id)
        #expect(s.activeProfileID == mom.id)
    }

    // A LOCKED FAMILY MUST NOT KEEP FILING TO-DOS UNDER A HIDDEN PERSON.
    //
    // `activeID` is a persisted device setting and locking deliberately hides
    // profiles without deleting anything, so a lapse while viewing Mum left
    // `activeProfileID` pointing at Mum — with no switcher and no assignee picker
    // on screen to reveal or change it. Add and Review seed the new item's owner
    // from this, and TaskLimit counts the free cap against the same bucket, so
    // every new to-do was silently filed under a profile the user couldn't see.
    @Test func lockedFamilyFilesNewItemsUnderTheOwner() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)
        s.setActive(mom.id)
        #expect(s.activeProfileID == mom.id)

        s.familyUnlocked = false
        #expect(s.activeProfileID == owner.id)   // not Mom
        #expect(s.hasFamily == false)            // and nothing on screen says otherwise

        // Nothing was destroyed: resubscribing restores the selection exactly.
        s.familyUnlocked = true
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
        #expect(s.me?.id == owner.id)      // active fell back
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

    // A shared errand belongs to nobody in particular. It must NOT be charged to
    // every person's allowance — one family to-do eating four people's quota at
    // once is how a family of four silently loses a quarter of what they paid for.
    @Test func familyToDosAreTheirOwnBucket() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)

        let shared = ActionItem(title: "book family dentist", category: .medical)
        shared.profileID = nil                      // for everyone
        ctx.insert(shared)
        try ctx.save()

        #expect(TaskLimit.count(ctx, profileID: nil) == 1)
        #expect(TaskLimit.count(ctx, profileID: owner.id) == 0)
        #expect(TaskLimit.count(ctx, profileID: mom.id) == 0)
    }

    // MARK: what the Inbox shows

    @Test func everyoneScopeShowsAllAndMineIncludesFamilyToDos() throws {
        let ctx = try context()
        let s = store()
        let owner = s.ensureOwnerProfile(ctx, name: "Jing")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)
        s.setActive(owner.id)

        // Everyone: nothing is filtered out.
        s.scope = .everyone
        #expect(s.isVisible(profileID: owner.id))
        #expect(s.isVisible(profileID: mom.id))
        #expect(s.isVisible(profileID: nil))

        // Just mine: my own AND the family's, but not Mom's.
        s.scope = .mine
        #expect(s.isVisible(profileID: owner.id))
        #expect(s.isVisible(profileID: nil))        // shared errands are everyone's
        #expect(!s.isVisible(profileID: mom.id))

        // Switching who this phone belongs to switches what "mine" means.
        s.setActive(mom.id)
        #expect(s.isVisible(profileID: mom.id))
        #expect(!s.isVisible(profileID: owner.id))
    }

    @Test func scopeDefaultsToEveryoneAndPersists() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        #expect(ProfileStore(defaults: d).scope == .everyone)   // the family view is the default
        let first = ProfileStore(defaults: d)
        first.scope = .mine
        #expect(ProfileStore(defaults: d).scope == .mine)       // survives a relaunch
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

    // MARK: family locks when Plus ends

    // Family profiles are the thing Plus is sold on, so they have to switch off
    // when the subscription does — every screen asks `hasFamily`, so the gate
    // lives there and no screen can be missed.
    @Test func familyLocksWhenPlusEnds() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Me")
        _ = try s.add(name: "Mom", plus: true, in: ctx)
        #expect(s.hasFamily)

        s.familyUnlocked = false
        #expect(!s.hasFamily)          // switcher, assignee row, scope toggle all vanish
        #expect(s.profiles.count == 2) // …but NOBODY is deleted
    }

    // THE TRAP THIS AVOIDS. Plus ends while the user is viewing "just mine" as
    // Mom: the switcher disappears with `hasFamily`, so if the filter kept
    // applying, their own to-dos would look deleted with no control left to bring
    // them back. Locked has to mean one plain list of everything.
    @Test func aLockedFamilyNeverHidesAToDo() throws {
        let ctx = try context()
        let s = store()
        s.ensureOwnerProfile(ctx, name: "Me")
        let mom = try s.add(name: "Mom", plus: true, in: ctx)
        s.setActive(mom.id)            // viewing Mom's list…
        s.scope = .mine                // …filtered to just her
        let someoneElse = UUID()

        // Unlocked: "just mine" really does filter the other person out.
        #expect(s.isVisible(profileID: mom.id))
        #expect(!s.isVisible(profileID: someoneElse))

        // Locked: everything is visible regardless of scope or who's active.
        s.familyUnlocked = false
        #expect(s.isVisible(profileID: mom.id))
        #expect(s.isVisible(profileID: someoneElse))
        #expect(s.isVisible(profileID: nil))
    }
}
