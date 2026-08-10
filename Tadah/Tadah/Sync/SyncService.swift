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

    // MARK: - cursors (per user, so switching accounts can't cross streams)

    private static func cursorKey(_ userID: String) -> String { "sync.cursor.\(userID)" }
    private static func watermarkKey(_ userID: String) -> String { "sync.pushedAt.\(userID)" }

    static func cursor(_ userID: String, _ d: UserDefaults = .standard) -> String {
        d.string(forKey: cursorKey(userID)) ?? ""
    }
    static func watermark(_ userID: String, _ d: UserDefaults = .standard) -> Date {
        (d.object(forKey: watermarkKey(userID)) as? Date) ?? .distantPast
    }
    // Push everything local on the next sync (used when seeding a new account or
    // keeping local items after signing into an existing one).
    static func resetWatermark(_ userID: String, _ d: UserDefaults = .standard) {
        d.set(Date.distantPast, forKey: watermarkKey(userID))
    }
    // Pull everything from the server on the next sync (used by "replace local").
    static func resetCursor(_ userID: String, _ d: UserDefaults = .standard) {
        d.set("", forKey: cursorKey(userID))
    }
    // Push nothing local on the next sync (the other half of "replace local").
    static func suppressPush(_ userID: String, _ d: UserDefaults = .standard) {
        d.set(Date.now, forKey: watermarkKey(userID))
    }

    // MARK: - one full round trip

    @discardableResult
    static func sync(context: ModelContext,
                     userID: String,
                     defaults: UserDefaults = .standard) async throws -> Outcome {
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
        let mark = watermark(userID, defaults)

        // ── gather local work ────────────────────────────────────────────────
        let localItems = (try? context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { !$0.isExample }))) ?? []
        let changed = localItems.filter { $0.updatedAt > mark }
        let stones = (try? context.fetch(FetchDescriptor<TaskTombstone>())) ?? []

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
        let outChanges: [Wire.Change] = try changed.map {
            try wire(TaskDTO($0), id: $0.id, updatedAt: $0.updatedAt)
        }
        let outDeletes = stones.map { Wire.Delete(id: $0.id.uuidString, deletedAt: iso($0.deletedAt)) }

        // Family profiles ride the same request — a profile and the to-dos inside
        // it must never land on a device one without the other.
        let localProfiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        let changedProfiles = localProfiles.filter { $0.updatedAt > mark }
        let profileStones = (try? context.fetch(FetchDescriptor<ProfileTombstone>())) ?? []
        let outProfiles: [Wire.Change] = try changedProfiles.map {
            try wire(ProfileDTO($0), id: $0.id, updatedAt: $0.updatedAt)
        }
        let outProfileDeletes = profileStones.map {
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
        func decodeAll<T: Decodable>(_ wire: [Wire.Change], as: T.Type) throws -> [T] {
            try wire.map {
                guard let d = $0.payload.data(using: .utf8),
                      let dto = try? decoder.decode(T.self, from: d) else { throw SyncError.decode }
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
        // Profiles FIRST: a task referencing a new profile should find it there.
        applyProfiles(changes: incomingProfiles, deletes: profileRemovals, in: context)
        let applied = apply(changes: incoming, deletes: taskRemovals, in: context)

        // ── commit progress (only now that the server has confirmed) ─────────
        defaults.set(payload.cursor, forKey: cursorKey(userID))
        defaults.set(attemptedAt, forKey: watermarkKey(userID))
        for stone in stones { context.delete(stone) }              // server has them now
        for stone in profileStones { context.delete(stone) }

        return Outcome(pushedChanges: outChanges.count, pushedDeletes: outDeletes.count,
                       appliedChanges: applied.changes, appliedDeletes: applied.deletes,
                       hasMore: payload.more ?? false)
    }

    // Merge family profiles, same last-writer-wins rule as tasks.
    //
    // A pulled profile deletion removes the person AND their to-dos on this device,
    // matching what the device that did the removing saw. Those items are deleted
    // directly (not via ItemActions) — the removing device already sent tombstones
    // for them, so writing more here would echo the same deletions back.
    @discardableResult
    static func applyProfiles(changes: [ProfileDTO],
                              deletes: [Removal],
                              in context: ModelContext) -> (changes: Int, deletes: Int) {
        let existing = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var appliedChanges = 0, appliedDeletes = 0

        for dto in changes {
            if let local = byID[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }   // local is newer
                dto.apply(to: local)
            } else {
                let profile = dto.makeProfile()
                context.insert(profile)
                byID[dto.id] = profile
            }
            appliedChanges += 1
        }

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
            let owned = (try? context.fetch(FetchDescriptor<ActionItem>(
                predicate: #Predicate { $0.profileID == id }))) ?? []
            for item in owned {
                // Per-task last-writer-wins, not a blanket cascade. Removing a
                // person on another device must not silently destroy a to-do of
                // theirs that someone edited here more recently. A survivor is
                // reassigned to the family (nil) so it stays visible and isn't
                // stranded pointing at a profile that no longer exists.
                if item.updatedAt > removal.deletedAt {
                    item.profileID = nil
                    continue
                }
                ReminderScheduler.shared.cancel(itemID: item.id)
                context.delete(item)
            }
            context.delete(local)
            byID[removal.id] = nil
            appliedDeletes += 1
        }
        return (appliedChanges, appliedDeletes)
    }

    // MARK: - apply (pure enough to unit-test without a network)

    // Merge server state into the local store using last-writer-wins. Returns how
    // much actually landed (a stale server copy is skipped, not applied).
    @discardableResult
    static func apply(changes: [TaskDTO],
                      deletes: [Removal],
                      in context: ModelContext) -> (changes: Int, deletes: Int) {
        let existing = (try? context.fetch(FetchDescriptor<ActionItem>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var appliedChanges = 0, appliedDeletes = 0

        for dto in changes {
            if let local = byID[dto.id] {
                guard dto.updatedAt > local.updatedAt else { continue }   // local is newer → keep it
                dto.apply(to: local)
                ReminderScheduler.shared.reschedule(for: local)
            } else {
                let item = dto.makeItem()
                context.insert(item)
                byID[dto.id] = item
                ReminderScheduler.shared.reschedule(for: item)
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
            ReminderScheduler.shared.cancel(itemID: removal.id)
            // context.delete directly — NOT ItemActions.delete, which would write a
            // tombstone and echo this deletion back to the server.
            context.delete(local)
            byID[removal.id] = nil
            appliedDeletes += 1
        }
        return (appliedChanges, appliedDeletes)
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
