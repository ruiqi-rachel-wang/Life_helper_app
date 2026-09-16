//  SchemaVersioningTests.swift
//
//  Proves the versioned container (TadahSchemaV1…V3 + TadahMigrationPlan) opens a
//  store created by the model that BUILD 2 SHIPPED — i.e. what every tester's
//  device actually has on disk — without losing data.
//
//  ⚠️ THE FIXTURE MUST BE THE FROZEN V1 MODEL, NOT `ActionItem`. The original
//  version of this test built its "legacy" store from `ActionItem` — the CURRENT
//  model — and called that V1. It proved nothing, because TadahSchemaV1 pointed at
//  that same live type: the fixture moved forward with the code and the test
//  passed no matter what.
//
//  Written honestly (against `TadahSchemaV1.ActionItem`, frozen at build 2's
//  property set) it FAILED with `loadIssueModelContainer` — a real build-2 store
//  matched no declared version and could not be opened at all. Fixing that meant
//  giving V1/V2 their own frozen nested models; this test is what pins it.
//
//  If this test fails, DO NOT SHIP: testers' stores won't open. TadahApp now
//  (correctly) refuses to delete an unopenable store, so they'd get an in-memory
//  session and a "couldn't open your to-dos" alert instead of losing everything —
//  recoverable, but still a broken update.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

struct SchemaVersioningTests {

    // The real upgrade path: a store written by build 2's MODEL SHAPE (fewer
    // properties, unversioned container) must open under the current versioned
    // container with every field intact.
    @MainActor
    @Test func versionedContainerOpensBuild2StoreWithDataIntact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }

        // 1) Create + fill a store the way build 2 did: the OLD property set, in a
        //    plain UNversioned ModelContainer.
        do {
            let v1 = Schema(versionedSchema: TadahSchemaV1.self)
            let legacy = try ModelContainer(
                for: v1, configurations: ModelConfiguration(schema: v1, url: url))
            let context = ModelContext(legacy)
            let item = TadahSchemaV1.ActionItem(title: "Electric bill", category: .utility)
            item.amount = Decimal(string: "42.17")
            item.dueDate = .now.addingTimeInterval(86400)
            item.steps = [ChecklistStep(text: "Pay it")]
            item.notes = ["June statement"]
            item.otherIDs = [DocID(label: "Account", value: "12345")]
            item.reminders = [ReminderItem(date: .now.addingTimeInterval(3600))]
            context.insert(item)
            try context.save()
        }

        // 2) Reopen the SAME file the way the app now does (versioned + plan).
        let versioned = try TadahApp.versionedContainer(url: url)
        let fetched = try ModelContext(versioned).fetch(FetchDescriptor<ActionItem>())

        #expect(fetched.count == 1)
        let item = try #require(fetched.first)
        #expect(item.title == "Electric bill")
        #expect(item.amount == Decimal(string: "42.17"))
        #expect(item.steps.count == 1)
        #expect(item.notes == ["June statement"])
        #expect(item.otherIDs.count == 1)
        #expect(item.reminders.count == 1)
        // The properties added AFTER build 2 must arrive with usable defaults
        // rather than crashing or nulling the row out.
        #expect(item.profileID == nil)
        #expect(item.updatedAt.timeIntervalSince1970 > 0)
    }

    @MainActor
    @Test func v3StoreMigratesWithTasksAndProfilesIntact() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v3-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let profileID = UUID()
        do {
            let schema = Schema(versionedSchema: TadahSchemaV3.self)
            let legacy = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(legacy)
            let profile = Profile(name: "Mom", id: profileID)
            profile.reminderMinutes = 570
            context.insert(profile)
            let item = TadahSchemaV3.ActionItem(title: "Water bill", category: .utility)
            item.profileID = profileID
            item.steps = [ChecklistStep(text: "Call billing", detail: StepDetail(explanation: "Check the charges", script: "Ask why the amount changed"))]
            item.notes = ["Keep this note"]
            context.insert(item)
            try context.save()
        }
        let current = try TadahApp.versionedContainer(url: url)
        let context = ModelContext(current)
        let item = try #require(try context.fetch(FetchDescriptor<ActionItem>()).first)
        #expect(item.title == "Water bill")
        #expect(item.profileID == profileID)
        #expect(item.steps.first?.detail?.script == "Ask why the amount changed")
        #expect(item.notes == ["Keep this note"])
        #expect(item.callOfferJSON.isEmpty)
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        #expect(profile.id == profileID)
        #expect(profile.name == "Mom")
        #expect(profile.reminderMinutes == 570)
    }

    // The store this test writes is the one every tester has. If it can't be
    // opened, TadahApp must NOT delete it — losing everyone's to-dos silently is
    // worse than any error state. This pins that policy.
    @MainActor
    @Test func unopenableStoreIsNeverDeleted() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // Not a SwiftData store at all — opening it must fail.
        try Data("this is not a database".utf8).write(to: url)
        #expect(throws: (any Error).self) { try TadahApp.versionedContainer(url: url) }

        // The bytes are still there, untouched, for a later build to recover.
        let after = try #require(try? Data(contentsOf: url))
        #expect(after == Data("this is not a database".utf8))
    }

    // V2 (sync foundation) adds ActionItem.updatedAt + the TaskTombstone model.
    // Confirm the versioned container stores and reads back BOTH models.
    @MainActor
    @Test func v2ContainerStoresTasksAndTombstones() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let container = try TadahApp.versionedContainer(url: url)
        let context = ModelContext(container)
        let item = ActionItem(title: "Rent", category: .housing)
        context.insert(item)
        let deletedID = UUID()
        context.insert(TaskTombstone(id: deletedID))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ActionItem>()).count == 1)
        let stones = try context.fetch(FetchDescriptor<TaskTombstone>())
        #expect(stones.count == 1)
        #expect(stones.first?.id == deletedID)
        // updatedAt is stamped at creation.
        #expect(abs(item.updatedAt.timeIntervalSinceNow) < 5)
    }
}
