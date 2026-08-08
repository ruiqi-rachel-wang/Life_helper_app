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

        let applied = SyncService.apply(changes: [], deletes: [local.id], in: ctx)
        try ctx.save()

        #expect(applied.deletes == 1)
        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<TaskTombstone>()).isEmpty)   // no echo
    }

    @Test func deleteForUnknownItemIsIgnored() throws {
        let ctx = try context()
        let applied = SyncService.apply(changes: [], deletes: [UUID()], in: ctx)
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

        let applied = SyncService.applyProfiles(changes: [], deletes: [mom.id], in: ctx)
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
