//  SyncServiceTests.swift
//
//  Phase 3: the merge rules. These exercise SyncService.apply directly (no
//  network), because that's where a bug would silently destroy a user's data —
//  a stale server copy overwriting a fresh local edit, or a pulled delete that
//  boomerangs back and deletes the account's copy too.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

@MainActor
struct SyncServiceTests {

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func item(_ title: String, updated: Date) -> ActionItem {
        let i = ActionItem(title: title, category: .utility)
        i.updatedAt = updated
        return i
    }

    @Test func newerServerChangeOverwritesLocal() throws {
        let ctx = try context()
        let local = item("old title", updated: Date(timeIntervalSince1970: 1000))
        ctx.insert(local)

        var dto = TaskDTO(local)
        dto.title = "new title"
        dto.updatedAt = Date(timeIntervalSince1970: 2000)   // server is newer

        let applied = SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(applied.changes == 1)
        #expect(local.title == "new title")
    }

    @Test func staleServerChangeDoesNotClobberLocalEdit() throws {
        let ctx = try context()
        let local = item("my fresh edit", updated: Date(timeIntervalSince1970: 5000))
        ctx.insert(local)

        var dto = TaskDTO(local)
        dto.title = "stale server copy"
        dto.updatedAt = Date(timeIntervalSince1970: 1000)   // older than local

        let applied = SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(applied.changes == 0)
        #expect(local.title == "my fresh edit")             // local wins
    }

    @Test func unknownServerChangeIsInserted() throws {
        let ctx = try context()
        let dto = TaskDTO(item("from another device", updated: Date(timeIntervalSince1970: 2000)))

        let applied = SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(applied.changes == 1)
        let all = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(all.count == 1)
        #expect(all.first?.title == "from another device")
    }

    // A delete pulled FROM the server must not write a tombstone — that would be
    // echoed back on the next push and delete the row for every other device.
    @Test func serverDeleteRemovesLocallyWithoutTombstone() throws {
        let ctx = try context()
        let local = item("deleted elsewhere", updated: Date(timeIntervalSince1970: 1000))
        ctx.insert(local)
        try ctx.save()

        // A tombstone stamped AFTER the local item's updatedAt — a genuinely newer
        // deletion, so it should win.
        let applied = SyncService.apply(
            changes: [],
            deletes: [SyncService.Removal(id: local.id, deletedAt: Date(timeIntervalSince1970: 2000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 1)
        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<TaskTombstone>()).isEmpty)   // no echo
    }

    // THE REGRESSION THIS FILE EXISTS FOR. Deletions used to be applied
    // unconditionally, so this sequence lost real work: another device deletes a
    // task, you edit that same task here while the sync is in flight, and the
    // OLDER server tombstone erased your NEWER edit. A delete is a write like any
    // other — it only wins if it's newer.
    @Test func staleServerDeleteDoesNotEraseNewerLocalEdit() throws {
        let ctx = try context()
        let local = item("edited while syncing", updated: Date(timeIntervalSince1970: 5000))
        ctx.insert(local)
        try ctx.save()

        let applied = SyncService.apply(
            changes: [],
            deletes: [SyncService.Removal(id: local.id, deletedAt: Date(timeIntervalSince1970: 1000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 0)
        let survivors = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.title == "edited while syncing")
    }

    // Same rule for family profiles: a stale removal must not delete a profile
    // (and everything inside it) that was just renamed here.
    @Test func staleProfileDeleteDoesNotEraseNewerLocalProfile() throws {
        let ctx = try context()
        let mom = Profile(name: "Mom", colorIndex: 1)
        mom.updatedAt = Date(timeIntervalSince1970: 5000)
        ctx.insert(mom)
        let hers = ActionItem(title: "her bill", category: .utility)
        hers.profileID = mom.id
        ctx.insert(hers)
        try ctx.save()

        let applied = SyncService.applyProfiles(
            changes: [],
            deletes: [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 1000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 0)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).count == 1)
    }

    // Removing a family member on another device must not destroy a to-do of
    // theirs that was edited MORE RECENTLY here. The cascade used to delete every
    // child task unconditionally once the profile deletion won, so a newer edit
    // was lost even though last-writer-wins should have saved it. Survivors become
    // family to-dos (nil) rather than pointing at a profile that no longer exists.
    @Test func profileDeletionSparesTasksEditedAfterIt() throws {
        let ctx = try context()
        let mom = Profile(name: "Mom", colorIndex: 1)
        mom.updatedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(mom)

        let stale = item("old one of hers", updated: Date(timeIntervalSince1970: 1000))
        stale.profileID = mom.id
        let fresh = item("edited here just now", updated: Date(timeIntervalSince1970: 9000))
        fresh.profileID = mom.id
        ctx.insert(stale); ctx.insert(fresh)
        try ctx.save()

        let applied = SyncService.applyProfiles(
            changes: [],
            deletes: [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 5000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 1)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).isEmpty)
        let survivors = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.title == "edited here just now")
        #expect(survivors.first?.profileID == nil)     // reassigned to the family
    }

    // The account always has exactly one owner. The server can't enforce that —
    // profile payloads are opaque to it — so a tombstone naming the owner is
    // corrupt or hostile and must be ignored, or the device is left with no owner
    // and every task orphaned.
    @Test func ownerProfileCannotBeDeletedByAServerTombstone() throws {
        let ctx = try context()
        let owner = Profile(name: "Jing", colorIndex: 0, isOwner: true)
        owner.updatedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(owner)
        let mine = ActionItem(title: "my bill", category: .utility)
        mine.profileID = owner.id
        ctx.insert(mine)
        try ctx.save()

        let applied = SyncService.applyProfiles(
            changes: [],
            deletes: [SyncService.Removal(id: owner.id, deletedAt: Date(timeIntervalSince1970: 9000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 0)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).count == 1)
    }

    @Test func deleteForUnknownItemIsIgnored() throws {
        let ctx = try context()
        let applied = SyncService.apply(
            changes: [],
            deletes: [SyncService.Removal(id: UUID(), deletedAt: .now)],
            in: ctx)
        #expect(applied.deletes == 0)
    }

    // Photos live only on the device that scanned them; a pulled update must not
    // blank one out.
    @Test func applyingServerChangeKeepsLocalPhoto() throws {
        let ctx = try context()
        let local = item("bill", updated: Date(timeIntervalSince1970: 1000))
        local.imageData = Data([0xAA, 0xBB])
        ctx.insert(local)

        var dto = TaskDTO(local)
        dto.title = "bill (edited on phone)"
        dto.updatedAt = Date(timeIntervalSince1970: 3000)

        SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(local.title == "bill (edited on phone)")
        #expect(local.imageData == Data([0xAA, 0xBB]))
    }

    // MARK: cursors

    @Test func cursorHelpersAreScopedPerUser() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        #expect(SyncService.cursor("userA", d) == "")
        #expect(SyncService.watermark("userA", d) == .distantPast)

        d.set("2026-08-05T00:00:00Z", forKey: "sync.cursor.userA")
        #expect(SyncService.cursor("userA", d) == "2026-08-05T00:00:00Z")
        #expect(SyncService.cursor("userB", d) == "")      // other account unaffected

        SyncService.suppressPush("userA", d)
        #expect(SyncService.watermark("userA", d) > .distantPast)
        SyncService.resetWatermark("userA", d)
        #expect(SyncService.watermark("userA", d) == .distantPast)
        SyncService.resetCursor("userA", d)
        #expect(SyncService.cursor("userA", d) == "")
    }

    // The server compares these as plain strings, so they must sort lexically in
    // time order — including within the same second.
    @Test func isoStampsSortLexicallyByTime() {
        let earlier = SyncService.iso(Date(timeIntervalSince1970: 1000.100))
        let later = SyncService.iso(Date(timeIntervalSince1970: 1000.900))
        #expect(earlier < later)
        #expect(SyncService.iso(Date(timeIntervalSince1970: 1000)) <
                SyncService.iso(Date(timeIntervalSince1970: 2000)))
    }

    // MARK: family profiles (phase B)

    @Test func newerServerProfileWinsAndStaleIsIgnored() throws {
        let ctx = try context()
        let local = Profile(name: "Mom", colorIndex: 1)
        local.updatedAt = Date(timeIntervalSince1970: 5000)
        ctx.insert(local)

        var stale = ProfileDTO(local)
        stale.name = "STALE"
        stale.updatedAt = Date(timeIntervalSince1970: 1000)
        SyncService.applyProfiles(changes: [stale], deletes: [], in: ctx)
        #expect(local.name == "Mom")                      // local edit survives

        var fresh = ProfileDTO(local)
        fresh.name = "Mum"
        fresh.updatedAt = Date(timeIntervalSince1970: 9000)
        SyncService.applyProfiles(changes: [fresh], deletes: [], in: ctx)
        #expect(local.name == "Mum")
    }

    @Test func unknownServerProfileIsInserted() throws {
        let ctx = try context()
        let dto = ProfileDTO(Profile(name: "Dad", colorIndex: 2))
        let applied = SyncService.applyProfiles(changes: [dto], deletes: [], in: ctx)
        #expect(applied.changes == 1)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).first?.name == "Dad")
    }

    // Removing a person on one device must take their to-dos on every device —
    // and must NOT write new tombstones, or the deletions would echo back.
    @Test func pulledProfileDeleteRemovesTheirItemsWithoutEchoing() throws {
        let ctx = try context()
        let mom = Profile(name: "Mom", colorIndex: 1)
        ctx.insert(mom)
        let hers = ActionItem(title: "her bill", category: .utility)
        hers.profileID = mom.id
        let mine = ActionItem(title: "my bill", category: .utility)
        ctx.insert(hers); ctx.insert(mine)
        try ctx.save()

        let applied = SyncService.applyProfiles(
            changes: [],
            deletes: [SyncService.Removal(id: mom.id, deletedAt: .now)],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 1)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).isEmpty)
        let items = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(items.count == 1)
        #expect(items.first?.title == "my bill")
        #expect(try ctx.fetch(FetchDescriptor<TaskTombstone>()).isEmpty)   // no echo
    }

    @Test func profileDTORoundTripsThroughJSON() throws {
        let p = Profile(name: "Mom", colorIndex: 3, isOwner: false)
        p.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        p.updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(ProfileDTO.self, from: try enc.encode(ProfileDTO(p)))
        #expect(decoded == ProfileDTO(p))
    }
}
