//  TaskBackup.swift
//
//  On-device safety net for the user's tasks (Part 3 — the "back up before you
//  sync" foundation). Writes a JSON snapshot of all real items + tombstones to
//  Application Support, keeps the last few, and can restore one. This exists so
//  that NO destructive step — signing into an existing account and pulling its
//  tasks, or applying a sync that deletes items — can ever lose local data: we
//  snapshot first, and the snapshot is recoverable.
//
//  Local-only and free. Photos (imageData) aren't included (see TaskDTO); a
//  restore keeps whatever photos are already on the device.
//

import Foundation
import SwiftData

@MainActor
enum TaskBackup {
    static let keep = 5   // how many recent snapshots to retain

    // The file format. Versioned so a future shape change stays readable.
    struct File: Codable {
        var version = 1
        var createdAt = Date.now
        var tasks: [TaskDTO]
        var tombstones: [Tombstone]

        struct Tombstone: Codable, Equatable {
            var id: UUID
            var deletedAt: Date
        }
    }

    // MARK: snapshot

    // Write a snapshot of current real (non-example) items + tombstones, prune to
    // the most recent `keep`, and return the file URL. Best-effort: throws on IO
    // or fetch failure so a caller gating a destructive op can abort safely.
    @discardableResult
    static func snapshot(from context: ModelContext) throws -> URL {
        let items = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { !$0.isExample }))
        let stones = try context.fetch(FetchDescriptor<TaskTombstone>())
        let file = File(tasks: items.map(TaskDTO.init),
                        tombstones: stones.map { File.Tombstone(id: $0.id, deletedAt: $0.deletedAt) })

        let dir = try backupsDirectory()
        let url = dir.appending(path: "tasks-\(stamp(.now)).json")
        try encoder.encode(file).write(to: url, options: .atomic)
        pruneOldBackups()
        return url
    }

    // MARK: restore

    // Replace the device's real items + tombstones with a backup's contents.
    // Examples are left alone. Used to recover after an unwanted change.
    static func restore(from url: URL, into context: ModelContext) throws {
        let file = try decoder.decode(File.self, from: Data(contentsOf: url))
        for item in try context.fetch(FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample })) {
            context.delete(item)
        }
        for stone in try context.fetch(FetchDescriptor<TaskTombstone>()) {
            context.delete(stone)
        }
        for dto in file.tasks { context.insert(dto.makeItem()) }
        for t in file.tombstones { context.insert(TaskTombstone(id: t.id, deletedAt: t.deletedAt)) }
    }

    // MARK: listing

    // Existing snapshots, newest first.
    static func backups() -> [URL] {
        guard let dir = try? backupsDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.lastPathComponent.hasPrefix("tasks-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // timestamped name sorts by time
    }

    static var mostRecent: URL? { backups().first }

    // MARK: internals

    private static func pruneOldBackups() {
        for stale in backups().dropFirst(keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    private static func backupsDirectory() throws -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "backups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Filename-safe timestamp (no colons): 2026-08-05T02-30-00Z, lexically sortable.
    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return f.string(from: date)
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
