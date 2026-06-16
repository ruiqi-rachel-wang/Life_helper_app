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

    // Pure reducer — unit-tested without touching disk.
    static func from(_ events: [MetricEvent]) -> MetricsSummary {
        var s = MetricsSummary()
        for e in events {
            switch e.kind {
            case .confirmed:
                s.confirmed += 1
                if let src = e.source { s.bySource[src, default: 0] += 1 }
            case .completed:
                s.completed += 1
                if let onTime = e.onTime {
                    s.completedWithDue += 1
                    if onTime { s.completedOnTime += 1 }
                }
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

    static func record(_ kind: MetricEvent.Kind, source: String? = nil, onTime: Bool? = nil) {
        let event = MetricEvent(kind: kind, date: .now, source: source, onTime: onTime)
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
