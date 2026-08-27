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

        let applied = try SyncService.apply(changes: [dto], deletes: [], in: ctx)
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

        let applied = try SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(applied.changes == 0)
        #expect(local.title == "my fresh edit")             // local wins
    }

    @Test func unknownServerChangeIsInserted() throws {
        let ctx = try context()
        let dto = TaskDTO(item("from another device", updated: Date(timeIntervalSince1970: 2000)))

        let applied = try SyncService.apply(changes: [dto], deletes: [], in: ctx)
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
        let applied = try SyncService.apply(
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

        let applied = try SyncService.apply(
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

        let applied = try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 1000))],
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

        let applied = try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 5000))],
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

        let applied = try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: owner.id, deletedAt: Date(timeIntervalSince1970: 9000))],
            in: ctx)
        try ctx.save()

        #expect(applied.deletes == 0)
        #expect(try ctx.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<ActionItem>()).count == 1)
    }

    // THE BUG THIS TEST WAS TOO WEAK TO CATCH. The earlier version only checked
    // that the task SURVIVED and got reassigned — not that the incoming EDIT
    // landed. It didn't: profile deletion ran first, `touch()` made the local copy
    // newer than the DTO about to be applied, and the newer title from the other
    // device was silently dropped.
    //
    // Stages must run in the real order — profile changes, then tasks, then
    // profile deletions — and the edited title has to be there at the end.
    @Test func incomingEditSurvivesAProfileDeletionInTheSamePage() throws {
        let ctx = try context()
        let mom = Profile(name: "Mom", colorIndex: 1)
        mom.updatedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(mom)
        let hers = item("her bill", updated: Date(timeIntervalSince1970: 1000))
        hers.profileID = mom.id
        ctx.insert(hers)
        try ctx.save()

        // The same page carries a NEWER version of that task.
        var incoming = TaskDTO(hers)
        incoming.title = "her bill, just edited elsewhere"
        incoming.updatedAt = Date(timeIntervalSince1970: 9000)

        try SyncService.applyProfileChanges([], in: ctx)
        try SyncService.apply(changes: [incoming], deletes: [], in: ctx)
        try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 5000))],
            in: ctx)
        try ctx.save()

        let survivors = try ctx.fetch(FetchDescriptor<ActionItem>())
        #expect(survivors.count == 1)
        // The whole point: the edit is not lost.
        #expect(survivors.first?.title == "her bill, just edited elsewhere")
        #expect(survivors.first?.profileID == nil)     // reassigned to the family
    }

    // A survivor's reassignment has to be PUSHED, or every other device keeps
    // pointing at the deleted profile forever. That means bumping updatedAt.
    @Test func reassignedSurvivorIsTouchedSoItSyncs() throws {
        let ctx = try context()
        let mom = Profile(name: "Mom", colorIndex: 1)
        mom.updatedAt = Date(timeIntervalSince1970: 1000)
        ctx.insert(mom)
        let fresh = item("edited here", updated: Date(timeIntervalSince1970: 9000))
        fresh.profileID = mom.id
        ctx.insert(fresh)
        try ctx.save()

        try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: mom.id, deletedAt: Date(timeIntervalSince1970: 5000))],
            in: ctx)
        try ctx.save()

        #expect(fresh.profileID == nil)
        // Stamp moved to ~now, so the next push includes it.
        #expect(abs(fresh.updatedAt.timeIntervalSinceNow) < 5)
    }

    // Older devices pushed randomly-keyed owner profiles, so a pull can legitimately
    // deliver several. Exactly one must remain an owner — and the losers are
    // DEMOTED, not deleted, because they may carry a real person's name and to-dos.
    @Test func duplicateOwnersCollapseToOneWithoutLosingAnyone() throws {
        let ctx = try context()
        let oldest = ProfileDTO(Profile(name: "Jing", colorIndex: 0, isOwner: true))
        var second = ProfileDTO(Profile(name: "Jing on iPad", colorIndex: 1, isOwner: true))
        second.createdAt = Date(timeIntervalSince1970: 9_000_000)

        try SyncService.applyProfileChanges([oldest, second], canonicalOwner: nil, in: ctx)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 2)                               // nobody deleted
        #expect(all.filter(\.isOwner).count == 1)             // exactly one owner
    }

    @Test func deleteForUnknownItemIsIgnored() throws {
        let ctx = try context()
        let applied = try SyncService.apply(
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

        try SyncService.apply(changes: [dto], deletes: [], in: ctx)
        #expect(local.title == "bill (edited on phone)")
        #expect(local.imageData == Data([0xAA, 0xBB]))
    }

    // MARK: push watermark (paging)

    // THE TIED-TIMESTAMP BUG. A bare-timestamp watermark cannot page across
    // records that share an instant: with 26 changes all stamped T, the first push
    // sends 25 and sets the mark to T, and the next pass filters `updatedAt > T` —
    // permanently excluding record 26. Ties are ordinary here (a migration or a
    // bulk reassignment touches many rows in one instant), so the mark carries an
    // id and comparison is (timestamp, id).
    @Test func compositeWatermarkPagesAcrossATiedTimestamp() {
        let tied = Date(timeIntervalSince1970: 5000)
        let ids = (0..<26).map { _ in UUID() }.sorted { $0.uuidString < $1.uuidString }

        // Nothing sent yet: every record is pending.
        let start = SyncService.Watermark(at: .distantPast, id: nil)
        let firstPage = ids.filter { start.isBefore(tied, $0) }.prefix(25)
        #expect(firstPage.count == 25)

        // Mark lands on the LAST record actually sent — stamp AND id.
        let mark = SyncService.Watermark(at: tied, id: firstPage.last)
        let remaining = ids.filter { mark.isBefore(tied, $0) }

        // Exactly the 26th, and nothing already sent.
        #expect(remaining.count == 1)
        #expect(remaining.first == ids.last)
        // A bare-timestamp mark would have produced 0 here — the record lost.
    }

    @Test func watermarkTreatsANilIDAsNothingSentAtThatInstant() {
        let t = Date(timeIntervalSince1970: 5000)
        let mark = SyncService.Watermark(at: t, id: nil)
        #expect(mark.isBefore(t, UUID()))                       // still pending
        #expect(mark.isBefore(t.addingTimeInterval(1), UUID())) // newer, pending
        #expect(!mark.isBefore(t.addingTimeInterval(-1), UUID()))  // older, done
    }

    // A watermark must survive as ONE value. Written as two keys, a crash between
    // them left the stamp advanced with a stale id — exactly the torn state that
    // lets tied records be skipped.
    @Test func watermarkRoundTripsAsASingleValue() {
        let d = UserDefaults(suiteName: "wm.\(UUID().uuidString)")!
        let id = UUID()
        let at = Date(timeIntervalSince1970: 5000)
        SyncService.setWatermark(SyncService.Watermark(at: at, id: id), "userA", .tasks, d)

        let read = SyncService.watermark("userA", .tasks, d)
        #expect(read.at == at)
        #expect(read.id == id)
        // …and the streams don't share storage.
        #expect(SyncService.watermark("userA", .profiles, d).at == .distantPast)
    }

    // A watermark left by the previous two-key format must still load. Dropping
    // the id (rather than trusting a possibly-torn pair) re-sends at most one
    // already-applied page, which last-writer-wins absorbs.
    @Test func legacyTwoKeyWatermarkStillLoads() {
        let d = UserDefaults(suiteName: "wm.\(UUID().uuidString)")!
        let at = Date(timeIntervalSince1970: 7000)
        d.set(at, forKey: "sync.pushedAt.userA")

        let read = SyncService.watermark("userA", .tasks, d)
        #expect(read.at == at)
        #expect(read.id == nil)
    }

    // MARK: cursors

    @Test func cursorHelpersAreScopedPerUser() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        #expect(SyncService.cursor("userA", d) == "")
        #expect(SyncService.watermark("userA", .tasks, d).at == .distantPast)

        d.set("2026-08-05T00:00:00Z", forKey: "sync.cursor.userA")
        #expect(SyncService.cursor("userA", d) == "2026-08-05T00:00:00Z")
        #expect(SyncService.cursor("userB", d) == "")      // other account unaffected

        SyncService.setWatermark(.init(at: .now, id: nil), "userA", .tasks, d)
        #expect(SyncService.watermark("userA", .tasks, d).at > .distantPast)
        SyncService.resetWatermark("userA", d)
        #expect(SyncService.watermark("userA", .tasks, d).at == .distantPast)
    }

    // SIGNING BACK IN MUST NOT UPLOAD WHAT YOU DID WHILE SIGNED OUT.
    //
    // `suppressPush` is how that's enforced: it moves the watermark to now, so the
    // push filter (`updatedAt > watermark`) skips everything already on the device.
    // The opposite helper, `resetWatermark`, is for the other case — guest data
    // becoming a brand-new account's starting set — and the two must not be
    // confused, because one of them silently uploads a previous session's work.
    @Test func suppressPushSkipsEverythingAlreadyOnTheDevice() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let editedWhileSignedOut = Date.now

        SyncService.suppressPush("userA", d)

        // Both streams, or a family edit made while signed out would still travel.
        for stream in [SyncService.Stream.tasks, .profiles] {
            #expect(SyncService.watermark("userA", stream, d).at >= editedWhileSignedOut)
        }
        // Scoped per account, like every other watermark.
        #expect(SyncService.watermark("userB", .tasks, d).at == .distantPast)

        // And it's reversible: the first-sign-in path still pushes everything.
        SyncService.resetWatermark("userA", d)
        #expect(SyncService.watermark("userA", .tasks, d).at == .distantPast)
    }

    // THE PULL CURSOR AND THE PUSH WATERMARK ARE TWO DIFFERENT DECISIONS.
    //
    // suppressPush answers "what leaves this phone". It must not also decide "what
    // arrives", and for a while it effectively did: signing back into your own
    // account suppressed the push (right) while the stale cursor meant the server
    // only ever mentioned rows newer than last session (wrong). A task deleted on
    // the device while signed out was therefore never restored — the account still
    // held it, but it had not changed, so it was never sent again. Unreachable
    // from that phone, forever.
    @Test func resettingTheCursorDoesNotDisturbTheWatermark() {
        let d = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        d.set("2026-08-05T00:00:00Z", forKey: "sync.cursor.userA")
        d.set("2026-08-05T00:00:00Z", forKey: "sync.cursor.userB")
        SyncService.suppressPush("userA", d)
        let pushMark = SyncService.watermark("userA", .tasks, d).at

        SyncService.resetCursorForFullPull("userA")   // standard defaults, not `d`
        SyncService.resetCursorForFullPull("userA", d)

        // The whole account is pulled again…
        #expect(SyncService.cursor("userA", d) == "")
        // …without re-uploading what was already here.
        #expect(SyncService.watermark("userA", .tasks, d).at == pushMark)
        // …and no other account is touched.
        #expect(SyncService.cursor("userB", d) == "2026-08-05T00:00:00Z")
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
        try SyncService.applyProfileChanges([stale], in: ctx)
        #expect(local.name == "Mom")                      // local edit survives

        var fresh = ProfileDTO(local)
        fresh.name = "Mum"
        fresh.updatedAt = Date(timeIntervalSince1970: 9000)
        try SyncService.applyProfileChanges([fresh], in: ctx)
        #expect(local.name == "Mum")
    }

    @Test func unknownServerProfileIsInserted() throws {
        let ctx = try context()
        let dto = ProfileDTO(Profile(name: "Dad", colorIndex: 2))
        let applied = try SyncService.applyProfileChanges([dto], in: ctx)
        #expect(applied == 1)
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

        let applied = try SyncService.applyProfileDeletions(
            [SyncService.Removal(id: mom.id, deletedAt: .now)],
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
