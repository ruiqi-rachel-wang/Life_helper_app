//  SyncService.swift
//
//  Push local task changes to the account and pull the account's back (Part 3,
//  phase 3). Conflict rule is LAST-WRITER-WINS on `updatedAt`, applied on BOTH
//  sides: the Worker only overwrites a row when the incoming stamp is newer, and
//  `apply` here only overwrites a local item when the server's copy is newer.
//
//  Data-safety rules this file obeys (see the plan):
//   • The cursor / push watermark advance ONLY after the server returns 2xx —
//     a dropped response re-sends next time instead of losing the change
//     (same contract as Metrics.flush()).
//   • The push watermark is captured BEFORE gathering, so an edit made while the
//     request is in flight is picked up next round instead of being skipped.
//   • Tombstones are purged only after the server has accepted them.
//   • A 401 means the session was revoked (a free account signed in elsewhere) —
//     we surface it rather than silently dropping data.
//
//  Photos are not synced (see TaskDTO); applying a pulled change never touches
//  a device's local `imageData`.
//

import Foundation
import SwiftData

@MainActor
enum SyncService {

    enum SyncError: Error, Equatable {
        case notConfigured      // no Worker set (simulator dev) — stay local
        case noSession          // not signed in / no token yet
        case unauthorized       // 401: session revoked → signed out on another device
        case accountChanged     // signed out / switched account mid-request — abandon this pass
        case server(Int)
        case decode             // a record the server sent could not be read
        case encode             // a local record could not be serialized — never drop it
    }

    struct Outcome: Equatable {
        var pushedChanges = 0
        var pushedDeletes = 0
        var appliedChanges = 0
        var appliedDeletes = 0
        // The server had more rows than one page holds — the caller should sync
        // again immediately rather than wait for the next lifecycle event.
        var hasMore = false
    }

    // An incoming deletion, WITH its timestamp. The timestamp is the whole point:
    // a deletion is a write like any other and only wins if it's newer than what's
    // on this device. Reducing these to bare UUIDs is what let a stale server
    // tombstone erase a newer local edit.
    struct Removal: Equatable {
        let id: UUID
        let deletedAt: Date
    }

    // How many records one push may carry. MUST stay <= the Worker's
    // MAX_SYNC_BATCH, which is itself sized for D1 Free's 50-queries-per-
    // invocation ceiling (each record is one statement, plus the route's own
    // reads/writes). Paging here is what stops a device with hundreds of pending
    // edits from building a request the server can never accept.
    static let maxRecordsPerPush = 25

    // How far ahead of now a local timestamp may legitimately sit before it's
    // treated as a broken clock. Matches the Worker's own skew allowance.
    static let maxClockSkew: TimeInterval = 5 * 60

    // MARK: - cursors (per user, so switching accounts can't cross streams)

    private static func cursorKey(_ userID: String) -> String { "sync.cursor.\(userID)" }
    private static func watermarkKey(_ userID: String) -> String { "sync.pushedAt.\(userID)" }

    static func cursor(_ userID: String, _ d: UserDefaults = .standard) -> String {
        d.string(forKey: cursorKey(userID)) ?? ""
    }
    // The push watermark is COMPOSITE — (timestamp, id) — for the same reason the
    // pull cursor is.
    //
    // A bare timestamp cannot page safely across ties. With 26 records all stamped
    // T, the first push sends 25 and sets the mark to T; the next pass filters
    // `updatedAt > T` and record 26 is excluded FOREVER. Ties are not exotic here:
    // a bulk reassignment or a migration touches many rows in the same instant.
    // The id breaks the tie, so paging is exact.
    struct Watermark: Equatable {
        var at: Date
        var id: UUID?          // nil = "everything at `at` is still pending"

        // Strictly after the mark, in (timestamp, id) order.
        func isBefore(_ stamp: Date, _ itemID: UUID) -> Bool {
            if stamp != at { return stamp > at }
            guard let id else { return true }
            return itemID.uuidString > id.uuidString
        }
    }

    private static func watermarkIDKey(_ userID: String) -> String { "sync.pushedID.\(userID)" }

    // TASKS AND PROFILES GET THEIR OWN WATERMARKS.
    //
    // They shared one, and the page budget was spent in category order — profiles
    // first. So 25 changed profiles plus one changed task meant every single pass
    // sent the same 25 profiles, sent zero tasks, and then refused to advance the
    // shared mark (because the task stream had sent nothing). The task was starved
    // forever: never uploaded, on any pass, ever.
    //
    // With independent marks each stream advances on its own progress, so a busy
    // stream can no longer hold the other hostage.
    enum Stream: String {
        case tasks, profiles
        fileprivate var suffix: String { self == .tasks ? "" : ".profiles" }
    }

    // Stored as ONE value, not a timestamp key plus an id key.
    //
    // Two writes can tear: a crash between them leaves the stamp advanced with a
    // stale (or missing) id, which is precisely the state that lets tied records
    // be skipped — the bug the composite watermark exists to prevent. A single
    // dictionary either lands or it doesn't.
    static func watermark(_ userID: String,
                          _ stream: Stream = .tasks,
                          _ d: UserDefaults = .standard) -> Watermark {
        let key = watermarkKey(userID) + stream.suffix
        if let raw = d.dictionary(forKey: key) {
            let at = (raw["at"] as? Date) ?? .distantPast
            let id = (raw["id"] as? String).flatMap(UUID.init(uuidString:))
            return Watermark(at: at, id: id)
        }
        // Migration: a watermark written by the previous two-key format. Read the
        // stamp only and drop the id — re-sending one already-applied page is
        // harmless under last-writer-wins, whereas trusting a possibly-torn pair
        // is not.
        if let at = d.object(forKey: key) as? Date { return Watermark(at: at, id: nil) }
        return Watermark(at: .distantPast, id: nil)
    }

    static func setWatermark(_ mark: Watermark,
                             _ userID: String,
                             _ stream: Stream = .tasks,
                             _ d: UserDefaults = .standard) {
        var raw: [String: Any] = ["at": mark.at]
        if let id = mark.id { raw["id"] = id.uuidString }
        d.set(raw, forKey: watermarkKey(userID) + stream.suffix)
        d.removeObject(forKey: watermarkIDKey(userID) + stream.suffix)   // legacy
    }

    // Push everything local on the next sync (used when seeding a new account or
    // keeping local items after signing into an existing one).
    static func resetWatermark(_ userID: String, _ d: UserDefaults = .standard) {
        for stream in [Stream.tasks, .profiles] {
            setWatermark(Watermark(at: .distantPast, id: nil), userID, stream, d)
        }
    }
    // Push NOTHING that exists right now — future edits push as normal.
    //
    // Removed on 2026-08-13 as dead code (it was half of the old "replace my
    // tasks with the account's"), and deliberately brought back on 2026-08-15 for
    // a different job: work done while SIGNED OUT must not travel to the account
    // when you sign back in. Advancing the watermark to now is exactly that — the
    // account keeps what it had, and the device keeps what it has.
    //
    // Note it does NOT delete anything, which is why it's safe to have around
    // again: the old danger was `resetCursor` beside it, wiping local state to
    // take the server's copy. That one stays gone.
    static func suppressPush(_ userID: String, _ d: UserDefaults = .standard) {
        for stream in [Stream.tasks, .profiles] {
            setWatermark(Watermark(at: .now, id: nil), userID, stream, d)
        }
    }

    // MARK: - one full round trip

    // Takes the CONTAINER, not a context, and does all of its work in a private
    // one.
    //
    // The apply stage rolls back on failure, and rollback discards a context's
    // ENTIRE pending set — so sharing the main context meant a failed sync threw
    // away whatever the user had typed while the request was in flight. Their
    // edits are not ours to discard. A private context contains the rollback to
    // sync's own changes; SwiftData propagates the save to the main context, so
    // the UI still updates.
    @discardableResult
    static func sync(container: ModelContainer,
                     userID: String,
                     defaults: UserDefaults = .standard) async throws -> Outcome {
        // FLUSH THE MAIN CONTEXT FIRST. A private context sees only what is
        // PERSISTED — not what is merely pending on the main one. The normal
        // create/edit/delete paths nudge a sync without saving, so the isolated
        // pass would look at an empty store, push nothing, and then advance the
        // watermark past the very edit it never saw. That edit is then never sent
        // again. Persisting first is what makes the isolation safe rather than
        // lossy.
        if container.mainContext.hasChanges {
            try container.mainContext.save()
        }

        let context = ModelContext(container)
        // Never write the user's in-flight edits on sync's behalf.
        context.autosaveEnabled = false
        guard let endpoint = BackendConfig.syncEndpoint else { throw SyncError.notConfigured }
        guard let token = SessionStore.token else { throw SyncError.noSession }
        // The session must belong to the account this pass was started for.
        // Without this, signing out of A and into B mid-request would send A's
        // cursor with B's token and merge one account's data into the other's.
        guard SessionStore.userID == userID else { throw SyncError.accountChanged }

        // Captured BEFORE gathering: anything edited during the request keeps a
        // stamp newer than this and is caught on the next pass.
        let attemptedAt = Date.now
        let since = cursor(userID, defaults)
        let taskMark = watermark(userID, .tasks, defaults)
        let profileMark = watermark(userID, .profiles, defaults)

        // ── gather local work ────────────────────────────────────────────────
        //
        // THROWING fetches. These were `try? … ?? []`, which turned a storage
        // failure into "this device has nothing to push" — the request then
        // succeeded and the watermark advanced past edits that were never sent.
        // A read failure must abort the pass, not silently redefine the work.
        let localItems = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { !$0.isExample }))
        // REPAIR POISONED LOCAL STAMPS BEFORE SENDING.
        //
        // A device with a badly skewed clock can stamp a record in the year 9999.
        // The Worker clamps the envelope to now — but the LOCAL record kept its
        // future date, so the clamped copy coming back always LOST last-writer-wins
        // against it. The record stayed newer than the watermark, was resent every
        // pass, and could never be corrected by any other device: permanently
        // frozen and permanently re-uploading. Clamping locally, once, ends it.
        let horizon = Date.now.addingTimeInterval(maxClockSkew)
        for item in localItems where item.updatedAt > horizon {
            item.updatedAt = .now
        }
        for profile in try context.fetch(FetchDescriptor<Profile>()) where profile.updatedAt > horizon {
            profile.updatedAt = .now
        }

        let changed = localItems.filter { taskMark.isBefore($0.updatedAt, $0.id) }
        let stones = try context.fetch(FetchDescriptor<TaskTombstone>())

        // THROWING, not compactMap+try?. A record that fails to encode used to be
        // dropped from the push while the watermark advanced past it anyway — the
        // edit was then never sent again, so the user's change was lost silently.
        // Now an encode failure aborts the whole pass and nothing is committed.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        func wire<T: Encodable>(_ dto: T, id: UUID, updatedAt: Date) throws -> Wire.Change {
            guard let data = try? encoder.encode(dto),
                  let payload = String(data: data, encoding: .utf8) else { throw SyncError.encode }
            return Wire.Change(id: id.uuidString, payload: payload, updatedAt: iso(updatedAt))
        }
        // Family profiles ride the same request — a profile and the to-dos inside
        // it must never land on a device one without the other.
        let localProfiles = try context.fetch(FetchDescriptor<Profile>())
        let changedProfiles = localProfiles.filter { profileMark.isBefore($0.updatedAt, $0.id) }
        let profileStones = try context.fetch(FetchDescriptor<ProfileTombstone>())

        // ── PAGE the push ────────────────────────────────────────────────────
        //
        // The server can only accept maxRecordsPerPush records per request,
        // because every record becomes one D1 statement and D1 Free allows 50
        // queries per invocation. Sending everything at once meant a device with a
        // few hundred pending edits produced a request the server could NEVER
        // accept — it failed, the watermark never advanced, and the same doomed
        // request retried forever. That is a backup that silently never happens.
        //
        // Oldest-first, so progress is monotonic: each pass commits a watermark
        // past the records it actually sent, and `hasMore` brings the caller
        // straight back for the next slice.
        //
        // Profiles are taken FIRST within the budget: a task can reference a
        // profile, and the profile should not lag behind its tasks.
        // SEPARATE BUDGETS, not one shared pot spent in category order. Sharing it
        // meant a stream with a full page of work consumed the whole budget every
        // pass and the other stream never sent a single record.
        var taskBudget = maxRecordsPerPush / 2 + maxRecordsPerPush % 2
        var profileBudget = maxRecordsPerPush / 2
        func takeTasks<T>(_ items: [T]) -> [T] {
            let slice = Array(items.prefix(taskBudget)); taskBudget -= slice.count; return slice
        }
        func takeProfiles<T>(_ items: [T]) -> [T] {
            let slice = Array(items.prefix(profileBudget)); profileBudget -= slice.count; return slice
        }
        // Sorted by (stamp, id) — the SAME order the composite watermark advances
        // in, so "everything at or below the mark has been sent" is exactly true.
        func byStampThenID(_ a: (Date, UUID), _ b: (Date, UUID)) -> Bool {
            a.0 != b.0 ? a.0 < b.0 : a.1.uuidString < b.1.uuidString
        }
        let pageProfileStones = takeProfiles(profileStones.sorted {
            byStampThenID(($0.deletedAt, $0.id), ($1.deletedAt, $1.id)) })
        let pageProfiles = takeProfiles(changedProfiles.sorted {
            byStampThenID(($0.updatedAt, $0.id), ($1.updatedAt, $1.id)) })
        let pageStones = takeTasks(stones.sorted {
            byStampThenID(($0.deletedAt, $0.id), ($1.deletedAt, $1.id)) })
        let pageChanged = takeTasks(changed.sorted {
            byStampThenID(($0.updatedAt, $0.id), ($1.updatedAt, $1.id)) })

        let morePending = pageProfileStones.count < profileStones.count
            || pageProfiles.count < changedProfiles.count
            || pageStones.count < stones.count
            || pageChanged.count < changed.count

        let outChanges: [Wire.Change] = try pageChanged.map {
            try wire(TaskDTO($0), id: $0.id, updatedAt: $0.updatedAt)
        }
        let outDeletes = pageStones.map { Wire.Delete(id: $0.id.uuidString, deletedAt: iso($0.deletedAt)) }
        let outProfiles: [Wire.Change] = try pageProfiles.map {
            try wire(ProfileDTO($0), id: $0.id, updatedAt: $0.updatedAt)
        }
        let outProfileDeletes = pageProfileStones.map {
            Wire.Delete(id: $0.id.uuidString, deletedAt: iso($0.deletedAt))
        }

        // ── talk to the Worker ───────────────────────────────────────────────
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Tadah-Session")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try encoder.encode(Wire.Request(
            since: since, changes: outChanges, deletes: outDeletes,
            profiles: outProfiles, profileDeletes: outProfileDeletes))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.server(-1) }
        if http.statusCode == 401 { throw SyncError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }
        guard let payload = try? JSONDecoder().decode(Wire.Response.self, from: data) else { throw SyncError.decode }

        // ── decode EVERYTHING before applying ANYTHING ───────────────────────
        //
        // Truly all-or-nothing. Decoding tasks and applying them before profiles
        // were even parsed meant a malformed PROFILE left the task mutations
        // already written to the store while the cursor stayed put — so the next
        // pass replayed them on top of a half-changed store. All four collections
        // are decoded up front; a single bad record throws before any mutation.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        // THE ENVELOPE IS AUTHORITATIVE, not the payload.
        //
        // The server validates and, where necessary, REWRITES the envelope's id and
        // updatedAt — it rejects non-UUID ids and clamps future-dated stamps back
        // to now — while the payload is stored opaquely, exactly as the sending
        // device wrote it. Decoding only the payload therefore threw away the
        // server's corrections and reintroduced three bugs:
        //
        //   • sub-second ordering: the payload's ISO encoding drops fractional
        //     seconds, so two edits in the same second became a tie under LWW,
        //     while the envelope keeps the precision that separates them;
        //   • clamping: a device with a year-9999 clock had its envelope clamped,
        //     but the original future stamp still sat inside the payload and would
        //     have frozen that record forever;
        //   • identity: nothing checked that the payload's id matched the
        //     validated envelope id.
        //
        // So the envelope's values win, and a payload that disagrees on identity is
        // treated as corrupt rather than quietly preferred.
        func decodeAll<T: SyncEnvelopeBacked>(_ wire: [Wire.Change], as: T.Type) throws -> [T] {
            try wire.map { record in
                guard let d = record.payload.data(using: .utf8),
                      var dto = try? decoder.decode(T.self, from: d),
                      let envelopeID = UUID(uuidString: record.id),
                      let envelopeStamp = date(from: record.updatedAt) else { throw SyncError.decode }
                guard dto.id == envelopeID else { throw SyncError.decode }
                dto.updatedAt = envelopeStamp      // server-validated, full precision
                return dto
            }
        }
        func removals(_ wire: [Wire.Delete]) throws -> [Removal] {
            try wire.map {
                guard let id = UUID(uuidString: $0.id),
                      let at = date(from: $0.deletedAt) else { throw SyncError.decode }
                return Removal(id: id, deletedAt: at)
            }
        }
        let incoming = try decodeAll(payload.changes, as: TaskDTO.self)
        let taskRemovals = try removals(payload.deletes)
        let incomingProfiles = try decodeAll(payload.profiles ?? [], as: ProfileDTO.self)
        let profileRemovals = try removals(payload.profileDeletes ?? [])

        // The session can be revoked, or the user can sign out, while the request
        // is in flight. Re-check before touching the store so another account's
        // response can never be merged into it.
        guard SessionStore.userID == userID else { throw SyncError.accountChanged }

        // ── apply (nothing above here has mutated the store) ─────────────────
        //
        // ORDER IS LOad-BEARING, in three stages:
        //   1. profile CHANGES  — so a task arriving alongside a new person finds
        //                         that person already in the store.
        //   2. task changes/deletes — every incoming edit lands at its real stamp.
        //   3. profile DELETIONS — the cascade now sees the FINAL task state.
        //
        // Stage 3 must come last. When deletions ran first they had to guess at the
        // incoming tasks, and reassigning a survivor called `touch()` — which made
        // the local copy newer than the very DTO about to be applied, so stage 2
        // skipped it and the newer edit from the other device was silently lost.
        //
        // ALL OF IT ROLLS BACK TOGETHER. These stages mutate the ModelContext
        // without saving, so a throw partway through used to leave half-applied
        // changes sitting in the context — the coordinator caught the error, and
        // the next save (from anywhere in the app) would quietly persist that
        // partial state. `rollback()` discards the whole pending set so a failed
        // pass leaves the store exactly as it was.
        let applied: (changes: Int, deletes: Int)
        let rescheduled: [ActionItem]
        let toCancel: [UUID]
        do {
            let canonicalOwner = Profile.ownerID(forAccount: userID)
            try applyProfileChanges(incomingProfiles, canonicalOwner: canonicalOwner, in: context)
            let result = try apply(changes: incoming, deletes: taskRemovals, in: context)
            let profileResult = try applyProfileDeletions(profileRemovals, in: context)
            applied = (result.changes, result.deletes)
            rescheduled = result.needsReminderRefresh
            toCancel = result.cancel + profileResult.cancel
        } catch {
            context.rollback()
            throw error
        }

        // Only the tombstones we actually SENT are cleared; the rest go next page.
        for stone in pageStones { context.delete(stone) }          // server has them now
        for stone in pageProfileStones { context.delete(stone) }

        // Each stream advances on ITS OWN progress. A shared mark meant one busy
        // stream could hold the other's records hostage forever (25 profiles + 1
        // task: the task was never sent, and the mark never moved because the task
        // stream had sent nothing). Composite (stamp, id) so a tie can't strand a
        // record either.
        //
        // A stream that sent everything jumps to `attemptedAt`; a stream that was
        // cut short lands exactly on the last record it sent.
        func advanced(sent: Int, of total: Int, last: (Date, UUID)?, from mark: Watermark) -> Watermark {
            guard sent < total else { return Watermark(at: attemptedAt, id: nil) }
            guard let last else { return mark }        // sent none — don't move
            return Watermark(at: last.0, id: last.1)
        }
        let newTaskMark = advanced(
            sent: pageChanged.count, of: changed.count,
            last: pageChanged.last.map { ($0.updatedAt, $0.id) }, from: taskMark)
        let newProfileMark = advanced(
            sent: pageProfiles.count, of: changedProfiles.count,
            last: pageProfiles.last.map { ($0.updatedAt, $0.id) }, from: profileMark)

        // ── persist, THEN commit progress ────────────────────────────────────
        // The cursor and watermark used to be written before the store was saved.
        // A save failure (or a crash in between) left the device claiming it had
        // consumed a page it had actually dropped — the classic way to lose data
        // permanently, since the server never sends it again. Save first; if that
        // throws, nothing advances and the same page is retried next pass.
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        defaults.set(payload.cursor, forKey: cursorKey(userID))
        setWatermark(newTaskMark, userID, .tasks, defaults)
        setWatermark(newProfileMark, userID, .profiles, defaults)

        // Reminders are touched only AFTER the save has committed — in BOTH
        // directions. A rolled-back pass used to leave iOS holding notifications
        // for items that never landed, and (worse) to have already cancelled
        // notifications for items that still exist: rollback restores the store,
        // but it cannot un-cancel a notification.
        for id in toCancel { ReminderScheduler.shared.cancel(itemID: id) }
        for item in rescheduled { ReminderScheduler.shared.reschedule(for: item) }

        return Outcome(pushedChanges: outChanges.count, pushedDeletes: outDeletes.count,
                       appliedChanges: applied.changes, appliedDeletes: applied.deletes,
                       // More to send, or more to pull — either way, come straight back.
                       hasMore: (payload.more ?? false) || morePending)
    }

    // MARK: - profiles (two stages; see the ordering note in sync())

    // STAGE 1 — upserts. Runs BEFORE task changes, so a task arriving alongside a
    // new person finds that person already present.
    @discardableResult
    static func applyProfileChanges(_ changes: [ProfileDTO],
                                    canonicalOwner: UUID? = nil,
                                    in context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<Profile>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var applied = 0

        for dto in changes {
            if let local = byID[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }   // local is newer
                dto.apply(to: local)
            } else {
                let profile = dto.makeProfile()
                context.insert(profile)
                byID[dto.id] = profile
            }
            applied += 1
        }

        // Exactly ONE owner. Older devices pushed randomly-keyed owner profiles, so
        // a pull can legitimately deliver several.
        //
        // The CANONICAL id wins when it's present — picking merely the oldest could
        // demote the account-derived owner in favour of a legacy random one, which
        // would then be re-promoted on the next migration and flip-flop forever.
        // Losers are demoted, not deleted: a duplicate may carry a real person's
        // name and their to-dos.
        let owners = byID.values.filter(\.isOwner)
        if owners.count > 1 {
            let keeper = canonicalOwner.flatMap { id in owners.first { $0.id == id } }
                ?? owners.min(by: { $0.createdAt < $1.createdAt })
            if let keeper {
                for extra in owners where extra.id != keeper.id {
                    extra.isOwner = false
                    extra.touch()          // so the demotion propagates to the family
                }
            }
        }
        return applied
    }

    // STAGE 3 — deletions. Runs AFTER task changes have been applied, so the
    // cascade below compares against each task's FINAL state.
    //
    // A pulled profile deletion removes the person AND their to-dos on this device,
    // matching what the device that did the removing saw. Those items are deleted
    // directly (not via ItemActions) — the removing device already sent tombstones
    // for them, so writing more here would echo the same deletions back.
    @discardableResult
    // Returns the ids whose reminders should be cancelled — AFTER the save. Firing
    // cancellations inline was unsafe: rollback can restore the store, but it
    // cannot un-cancel a notification, so a failed pass silently disarmed alarms
    // for to-dos that still exist.
    static func applyProfileDeletions(_ deletes: [Removal],
                                      in context: ModelContext) throws -> (deletes: Int, cancel: [UUID]) {
        guard !deletes.isEmpty else { return (0, []) }
        let existing = try context.fetch(FetchDescriptor<Profile>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var applied = 0
        var cancel: [UUID] = []

        for removal in deletes {
            guard let local = byID[removal.id] else { continue }
            // Same last-writer-wins guard as tasks: a stale removal must not wipe a
            // profile someone just renamed on this device.
            guard removal.deletedAt > local.updatedAt else { continue }
            // NEVER delete the owner. The account always has exactly one owner
            // profile; the server can't enforce that (profile payloads are opaque
            // to it), so this is the only place that knows. A tombstone for the
            // owner is a corrupt or hostile record — ignore it rather than leave
            // the device with no owner and every task orphaned.
            guard !local.isOwner else { continue }

            let id = removal.id
            let owned = try context.fetch(FetchDescriptor<ActionItem>(
                predicate: #Predicate { $0.profileID == id }))
            for item in owned {
                // Per-task last-writer-wins, not a blanket cascade. Removing a
                // person on another device must not silently destroy a to-do of
                // theirs that someone edited more recently. Because this stage runs
                // after task changes, `item.updatedAt` already reflects anything
                // that arrived in this page — no guessing required.
                if item.updatedAt > removal.deletedAt {
                    // Survivor: reassign to the family so it stays visible instead
                    // of pointing at a profile that no longer exists. `touch()` is
                    // safe here (unlike in stage 1) precisely because no incoming
                    // DTO is applied after this point.
                    item.profileID = nil
                    item.touch()
                    continue
                }
                cancel.append(item.id)
                context.delete(item)
            }
            context.delete(local)
            byID[removal.id] = nil
            applied += 1
        }
        return (applied, cancel)
    }

    // MARK: - apply (pure enough to unit-test without a network)

    // Merge server state into the local store using last-writer-wins. Returns how
    // much actually landed (a stale server copy is skipped, not applied).
    // `needsReminderRefresh` is returned rather than scheduled here: notifications
    // must not be registered for changes that a later failure rolls back.
    @discardableResult
    static func apply(changes: [TaskDTO],
                      deletes: [Removal],
                      in context: ModelContext) throws
                      -> (changes: Int, deletes: Int,
                          needsReminderRefresh: [ActionItem], cancel: [UUID]) {
        // Throwing, like every other fetch in the sync path: reconciling against a
        // partially-read store silently produces wrong merge decisions.
        let existing = try context.fetch(FetchDescriptor<ActionItem>())
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var appliedChanges = 0, appliedDeletes = 0
        var needsReminderRefresh: [ActionItem] = []
        var cancel: [UUID] = []

        for dto in changes {
            if let local = byID[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }   // local is newer → keep it
                dto.apply(to: local)
                needsReminderRefresh.append(local)
            } else {
                let item = dto.makeItem()
                context.insert(item)
                byID[dto.id] = item
                needsReminderRefresh.append(item)
            }
            appliedChanges += 1
        }

        for removal in deletes {
            guard let local = byID[removal.id] else { continue }
            // LAST-WRITER-WINS applies to deletions too. This used to delete
            // unconditionally, which lost real work: another device deletes a task,
            // you edit that same task here while the sync is in flight, and the
            // OLDER server deletion erased your NEWER edit. Keeping the local item
            // also re-pushes it (its updatedAt is past the watermark), so the edit
            // wins on the server and the other device gets it back.
            guard removal.deletedAt > local.updatedAt else { continue }
            cancel.append(removal.id)
            // context.delete directly — NOT ItemActions.delete, which would write a
            // tombstone and echo this deletion back to the server.
            context.delete(local)
            byID[removal.id] = nil
            appliedDeletes += 1
        }
        return (appliedChanges, appliedDeletes, needsReminderRefresh, cancel)
    }

    // MARK: - helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    // Fractional seconds so two edits in the same second still order correctly —
    // the server compares these as plain strings, and ISO-8601 sorts lexically.
    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    // The inverse. Accepts a stamp without fractional seconds too, since the
    // Worker writes its own `now` (plain ISO) when it clamps a skewed client clock.
    private static let isoPlainFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(from string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoPlainFormatter.date(from: string)
    }

    enum Wire {
        struct Change: Codable { let id: String; let payload: String; let updatedAt: String }
        struct Delete: Codable { let id: String; let deletedAt: String }
        struct Request: Encodable {
            let since: String; let changes: [Change]; let deletes: [Delete]
            let profiles: [Change]; let profileDeletes: [Delete]
        }
        // profiles/profileDeletes are optional so a client still works against a
        // Worker that hasn't been redeployed with family support yet.
        struct Response: Decodable {
            let changes: [Change]; let deletes: [Delete]; let cursor: String
            let profiles: [Change]?; let profileDeletes: [Delete]?
            let more: Bool?
        }
    }
}
