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
        case server(Int)
        case decode
    }

    struct Outcome: Equatable {
        var pushedChanges = 0
        var pushedDeletes = 0
        var appliedChanges = 0
        var appliedDeletes = 0
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

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let outChanges: [Wire.Change] = changed.compactMap { item in
            guard let data = try? encoder.encode(TaskDTO(item)),
                  let payload = String(data: data, encoding: .utf8) else { return nil }
            return Wire.Change(id: item.id.uuidString, payload: payload, updatedAt: iso(item.updatedAt))
        }
        let outDeletes = stones.map { Wire.Delete(id: $0.id.uuidString, deletedAt: iso($0.deletedAt)) }

        // ── talk to the Worker ───────────────────────────────────────────────
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Tadah-Session")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try encoder.encode(Wire.Request(since: since, changes: outChanges, deletes: outDeletes))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.server(-1) }
        if http.statusCode == 401 { throw SyncError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw SyncError.server(http.statusCode) }
        guard let payload = try? JSONDecoder().decode(Wire.Response.self, from: data) else { throw SyncError.decode }

        // ── apply what came back ─────────────────────────────────────────────
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let incoming: [TaskDTO] = payload.changes.compactMap {
            guard let d = $0.payload.data(using: .utf8) else { return nil }
            return try? decoder.decode(TaskDTO.self, from: d)
        }
        let removals: [UUID] = payload.deletes.compactMap { UUID(uuidString: $0.id) }
        let applied = apply(changes: incoming, deletes: removals, in: context)

        // ── commit progress (only now that the server has confirmed) ─────────
        defaults.set(payload.cursor, forKey: cursorKey(userID))
        defaults.set(attemptedAt, forKey: watermarkKey(userID))
        for stone in stones { context.delete(stone) }   // server has them now

        return Outcome(pushedChanges: outChanges.count, pushedDeletes: outDeletes.count,
                       appliedChanges: applied.changes, appliedDeletes: applied.deletes)
    }

    // MARK: - apply (pure enough to unit-test without a network)

    // Merge server state into the local store using last-writer-wins. Returns how
    // much actually landed (a stale server copy is skipped, not applied).
    @discardableResult
    static func apply(changes: [TaskDTO],
                      deletes: [UUID],
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

        for id in deletes {
            guard let local = byID[id] else { continue }
            ReminderScheduler.shared.cancel(itemID: id)
            // context.delete directly — NOT ItemActions.delete, which would write a
            // tombstone and echo this deletion back to the server.
            context.delete(local)
            byID[id] = nil
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

    enum Wire {
        struct Change: Codable { let id: String; let payload: String; let updatedAt: String }
        struct Delete: Codable { let id: String; let deletedAt: String }
        struct Request: Encodable { let since: String; let changes: [Change]; let deletes: [Delete] }
        struct Response: Decodable { let changes: [Change]; let deletes: [Delete]; let cursor: String }
    }
}
