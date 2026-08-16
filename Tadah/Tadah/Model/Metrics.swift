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
import CryptoKit

// One logged moment in the confirm → complete loop.
nonisolated struct MetricEvent: Codable, Equatable {
    enum Kind: String, Codable { case confirmed, completed }
    var id = UUID()         // stable per-event id; the backend de-dupes uploads on it
    var kind: Kind
    var date: Date
    var itemID: UUID?       // which item — lets the summary de-dupe and match the funnel
    var source: String?     // scanned / guide / custom (on `confirmed`)
    var onTime: Bool?       // completed on/before the due date? nil if no due date

    init(kind: Kind, date: Date, itemID: UUID? = nil, source: String? = nil, onTime: Bool? = nil) {
        self.kind = kind; self.date = date
        self.itemID = itemID; self.source = source; self.onTime = onTime
    }

    // Custom decode so metrics.json files written before `id` existed still load —
    // a missing id just gets a fresh one (those events upload as new rows).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        date = try c.decode(Date.self, forKey: .date)
        itemID = try c.decodeIfPresent(UUID.self, forKey: .itemID)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        onTime = try c.decodeIfPresent(Bool.self, forKey: .onTime)
    }
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

    // Upload high-water mark: how many events (the log is append-only) we've already
    // sent to the backend. Lets flush() send only what's new.
    private static let syncedKey = "tadah.metrics.syncedCount"

    // Must stay <= the Worker's MAX_BATCH (D1 Free: 50 queries per invocation).
    static let maxEventsPerUpload = 25

    // User consent for uploading anonymous usage stats. Default true (opted in); the
    // Profile "Share anonymous usage data" toggle writes this same key. When off,
    // flush() no-ops — events still log locally, they just never leave the device.
    static let shareUsageKey = "tadah.metrics.shareUsage"
    static var uploadsEnabled: Bool {
        UserDefaults.standard.object(forKey: shareUsageKey) as? Bool ?? true   // unset → opted in
    }

    /// Migrate every persisted key from the app's former name ("cuevi.*") to
    /// the current one ("tadah.*") so testers who upgrade across the Cuevi→Tadah
    /// rename keep their settings: usage-sharing consent, install identity,
    /// upload cursor, save-photo-with-item preference, and the discreet
    /// lock-screen privacy toggle. Safe to call on every launch: each value
    /// moves only when the new key is unset and an old value exists, then the
    /// old key is cleared. Can be deleted once all installs are past this build.
    static func migrateLegacyKeysIfNeeded() {
        let d = UserDefaults.standard
        let renames = [
            ("cuevi.metrics.shareUsage",     shareUsageKey),
            ("cuevi.metrics.syncedCount",    syncedKey),
            ("cuevi.metrics.installID",      Install.idKey),
            ("cuevi.savePhotoWithItem",      AppSettings.savePhotoKey),
            ("cuevi.notifications.discreet", ReminderScheduler.discreetKey),
        ]
        for (old, new) in renames {
            guard d.object(forKey: new) == nil,        // never clobber an existing new value
                  let value = d.object(forKey: old) else { continue }
            d.set(value, forKey: new)
            d.removeObject(forKey: old)
        }
    }

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

    // Best-effort upload of events not yet sent. Safe to call often (launch /
    // foreground / background): no-ops when nothing is new, never blocks the UI,
    // and the backend de-dupes on event id, so a dropped response can't double
    // count. The local metrics.json stays the source of truth — we only advance
    // the cursor after the server confirms it stored the batch.
    static func flush() {
        guard uploadsEnabled else { return }                             // user opted out
        guard let endpoint = BackendConfig.eventsEndpoint else { return } // no Worker → stay local
        queue.async {
            let all = readFile()
            let synced = UserDefaults.standard.integer(forKey: syncedKey)
            guard all.count > synced else { return }               // nothing new
            // CHUNKED to the server's per-request limit, which is sized for D1
            // Free's 50-queries-per-invocation ceiling. Sending every pending
            // event at once meant a device that had been offline built a batch the
            // server could never store: it 413'd, the cursor never advanced, and
            // the same doomed upload retried forever. One chunk per flush; the
            // next flush (launch/background) takes the following one.
            let pending = Array(all[synced...].prefix(maxEventsPerUpload))
            let total = synced + pending.count

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601                 // readable occurred_at
            let envelope = UploadEnvelope(installID: Install.id,
                                          appVersion: Install.appVersion,
                                          events: pending.map(WireEvent.init))
            guard let body = try? encoder.encode(envelope) else { return }

            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !BackendConfig.proxyToken.isEmpty {
                req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
            }
            req.httpBody = body

            URLSession.shared.dataTask(with: req) { _, response, _ in
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return }   // retry next launch
                queue.async { UserDefaults.standard.set(total, forKey: syncedKey) }
            }.resume()
        }
    }

    // The JSON the Worker's /events route expects.
    private struct UploadEnvelope: Encodable {
        let installID: String
        let appVersion: String
        let events: [WireEvent]
    }

    // What actually goes over the wire.
    //
    // ⚠️ THE ITEM ID IS PSEUDONYMISED HERE, and it must stay that way. The local
    // event keeps the real `ActionItem.id` because the funnel needs to match a
    // confirm to its completion — but uploading that raw UUID made the analytics
    // re-identifiable: the very same UUID is stored as `tasks.item_id` next to
    // `tasks.user_id`, IN THE SAME D1 DATABASE. One JOIN turned every "anonymous"
    // product-interaction row into "this named Apple account did this".
    //
    // `funnelID` is HMAC(per-install salt, itemID). It is stable within an install
    // — so the confirm→complete funnel still works exactly as before — and is
    // unjoinable with anything else, because the salt never leaves the device.
    struct WireEvent: Encodable {
        let id: String
        let kind: String
        let date: Date
        let itemID: String?      // the HMAC, never the task's real UUID
        let source: String?
        let onTime: Bool?

        init(_ e: MetricEvent) {
            id = e.id.uuidString
            kind = e.kind.rawValue
            date = e.date
            itemID = e.itemID.map { Metrics.funnelID(for: $0) }
            source = e.source
            onTime = e.onTime
        }
    }

    // Per-install pseudonym for an item. HMAC (not a bare hash) because the input
    // space is guessable: a plain SHA-256 of a UUID could be recomputed by anyone
    // holding the task ids, which would defeat the whole point.
    static func funnelID(for itemID: UUID) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(itemID.uuidString.utf8),
            using: SymmetricKey(data: funnelSalt))
        return mac.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // Random, generated once per install, never uploaded. Losing it (reinstall)
    // just means the funnel restarts for that install, which is acceptable —
    // metrics are per-install anyway.
    private static let saltKey = "tadah.metrics.funnelSalt"
    private static var funnelSalt: Data {
        let d = UserDefaults.standard
        if let existing = d.data(forKey: saltKey) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // An all-zero salt would make the "pseudonym" trivially recomputable by
        // anyone holding the task ids, which is exactly the linkage this exists to
        // break. If the system RNG fails, fall back to UUIDs rather than ship a
        // known-weak key.
        let fresh: Data = status == errSecSuccess
            ? Data(bytes)
            : Data((UUID().uuidString + UUID().uuidString).utf8)
        d.set(fresh, forKey: saltKey)
        return fresh
    }

    #if DEBUG
    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: syncedKey)   // re-upload from scratch
    }
    #endif

    private static func readFile() -> [MetricEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([MetricEvent].self, from: data) else { return [] }
        return events
    }
}

// Anonymous identity for the metrics upload envelope. NO PII: a random UUID
// minted once and kept in UserDefaults — it labels a device *install*, never a
// person.
//
// ⚠️ THIS MUST STAY SEPARATE FROM `Device.id`. It used to be the same value: the
// analytics envelope sent it as `installID` while sign-in sent the identical
// string as `deviceId`, which the Worker stores in `sessions` next to the Apple
// user id. Anyone with both tables could join them and attach every "anonymous"
// event to a named account — so the data was not anonymous, and the privacy
// policy and manifest saying "not linked" were wrong. Two independent random ids
// are what make that claim true, so never collapse these back into one.
nonisolated enum Install {
    static let idKey = "tadah.metrics.installID"

    static var id: String { Self.stableID(forKey: idKey) }

    fileprivate static func stableID(forKey key: String) -> String {
        let d = UserDefaults.standard
        if let existing = d.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        d.set(fresh, forKey: key)
        return fresh
    }

    // e.g. "1.0 (3)" — marketing version + build, so events can be read per build.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

// The id that identifies this DEVICE to the account backend: it goes in the
// session row next to the Apple user id, and it's what the free "one device at a
// time" rule counts. Deliberately a DIFFERENT random value from `Install.id` —
// see the note there. This one is account-linked by design; the analytics one
// must never be.
nonisolated enum Device {
    static let idKey = "tadah.account.deviceID"

    static var id: String { Install.stableID(forKey: idKey) }
}
