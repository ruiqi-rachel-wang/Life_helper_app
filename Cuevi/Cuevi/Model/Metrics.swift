//  Metrics.swift
//
//  The one launch metric: of the action items a user CONFIRMS (adds to the
//  inbox), what fraction do they come back to COMPLETE — and on time? See the
//  build plan's "one metric that matters".
//
//  Local-only by design (no servers, matches the rest of the app): events are
//  appended to a small JSON file on the device, viewable/exportable from the
//  Profile tab's DEBUG section. Cross-tester roll-up would need a backend — a
//  Phase-2 concern; here we capture the data and let each device report itself.
//
//  Logging runs in every build; only the viewer is DEBUG-gated.
//

import Foundation

// One logged moment in the confirm → complete loop.
nonisolated struct MetricEvent: Codable, Equatable {
    enum Kind: String, Codable { case confirmed, completed }
    var kind: Kind
    var date: Date
    var itemID: UUID?       // which item — lets the summary de-dupe and match the funnel
    var source: String?     // scanned / guide / custom (on `confirmed`)
    var onTime: Bool?       // completed on/before the due date? nil if no due date
}

// Rolled-up numbers for the launch metric + a light breakdown by source.
nonisolated struct MetricsSummary: Equatable {
    var confirmed = 0
    var completed = 0
    var completedOnTime = 0      // done on or before the due date
    var completedWithDue = 0     // completed items that HAD a due date
    var bySource: [String: Int] = [:]   // confirmed count per source

    // Headline: of confirmed items, how many came back completed at all.
    var completionRate: Double { confirmed == 0 ? 0 : Double(completed) / Double(confirmed) }
    // Of completed items that had a due date, how many beat the deadline. This is
    // the "working vs. broken loop" number (>50% working, <30% broken).
    var onTimeRate: Double { completedWithDue == 0 ? 0 : Double(completedOnTime) / Double(completedWithDue) }

    // Pure reducer — unit-tested without touching disk. The funnel is PER ITEM
    // (keyed by itemID): of the items the user CONFIRMED, how many did they
    // complete, and on time. Keying by id de-dupes repeat completions (reopen →
    // re-done, stale notification taps) and ignores completions of items that
    // were never confirmed — e.g. the seeded dev samples, which are inserted
    // without a confirmed event. Id-less events (shouldn't occur) are skipped.
    static func from(_ events: [MetricEvent]) -> MetricsSummary {
        var confirmedSource: [UUID: String] = [:]    // itemID → source, first confirm wins
        var firstOnTime: [UUID: Bool?] = [:]         // itemID → onTime of the first completion
        for e in events {
            guard let id = e.itemID else { continue }
            switch e.kind {
            case .confirmed:
                if confirmedSource[id] == nil { confirmedSource[id] = e.source ?? "other" }
            case .completed:
                if !firstOnTime.keys.contains(id) { firstOnTime[id] = e.onTime }
            }
        }
        var s = MetricsSummary()
        s.confirmed = confirmedSource.count
        for src in confirmedSource.values { s.bySource[src, default: 0] += 1 }
        // Only completions of confirmed items count toward the funnel.
        for (id, onTime) in firstOnTime where confirmedSource[id] != nil {
            s.completed += 1
            if let onTime {                          // had a due date
                s.completedWithDue += 1
                if onTime { s.completedOnTime += 1 }
            }
        }
        return s
    }
}

// Append-only local log. A serial queue keeps writes (which can come from the
// notification handler off the main thread) from racing reads. Volume is tiny.
nonisolated enum Metrics {
    private static let queue = DispatchQueue(label: "com.notie.metrics")

    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("metrics.json")
    }()

    static func record(_ kind: MetricEvent.Kind, itemID: UUID? = nil, source: String? = nil, onTime: Bool? = nil) {
        let event = MetricEvent(kind: kind, date: .now, itemID: itemID, source: source, onTime: onTime)
        queue.async {
            var events = readFile()
            events.append(event)
            if let data = try? JSONEncoder().encode(events) {
                try? data.write(to: fileURL)
            }
        }
    }

    static func load() -> [MetricEvent] { queue.sync { readFile() } }

    static func summary() -> MetricsSummary { .from(load()) }

    // The file to hand to a ShareLink, or nil if nothing logged yet.
    static func exportURL() -> URL? {
        FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    #if DEBUG
    static func reset() { try? FileManager.default.removeItem(at: fileURL) }
    #endif

    private static func readFile() -> [MetricEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([MetricEvent].self, from: data) else { return [] }
        return events
    }
}
