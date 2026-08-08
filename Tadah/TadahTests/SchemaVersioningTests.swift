//  SchemaVersioningTests.swift
//
//  Proves the versioned container (TadahSchemaV1…V3 + TadahMigrationPlan) opens a
//  store created by the model that BUILD 2 SHIPPED — i.e. what every tester's
//  device actually has on disk — without losing data.
//
//  ⚠️ WHY THE FIXTURE IS A SEPARATE TYPE. The obvious version of this test builds
//  its "legacy" store from `ActionItem` and calls that V1. That proves nothing:
//  `ActionItem` is the CURRENT model and has gained `updatedAt` (V2) and
//  `profileID` (V3) since build 2, and TadahSchemaV1.models points at it too — so
//  the fixture silently moves forward with the code and the test passes no matter
//  what. `LegacyV1ActionItem` below is a hand-frozen copy of build 2's stored
//  properties under the same SwiftData entity name. Nothing in the app can change
//  it, so it keeps describing build 2 forever.
//
//  If this test fails, DO NOT SHIP: testers' stores won't open, and TadahApp now
//  (correctly) refuses to delete an unopenable store, so they'd get an in-memory
//  session and a "couldn't open your to-dos" alert instead of losing everything.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

// A frozen replica of the schema BUILD 2 SHIPPED. The model is NESTED inside the
// VersionedSchema (Apple's own pattern for pinning an old version) so its entity
// name is still "ActionItem" — SwiftData matches entities by type name, so a
// differently-named class would create a different table and test nothing.
//
// Keep these properties EXACTLY as build 2 had them: no `updatedAt`, no
// `profileID`. Never "fix" this to match the current model — that is precisely
// the drift that made the original test vacuous.
enum BuildTwoSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ActionItem.self] }

    @Model
    final class ActionItem {
        var id: UUID = UUID()
        var title: String = ""
        var category: ItemCategory = ItemCategory.other
        var amount: Decimal?
        var currency: String = "USD"
        var dueDate: Date?
        var note: String = ""
        @Attribute(.externalStorage) var imageData: Data?
        var status: WorkStatus = WorkStatus.todo
        var steps: [ChecklistStep] = []
        var recurrence: Recurrence?
        var seriesID: UUID?
        var recurrenceAnchorDay: Int?
        var isExample: Bool = false
        var createdAt: Date = Date.now
        var summary: String = ""
        var documentType: String = ""
        var sender: String = ""
        var senderShort: String = ""
        var dueHasTime: Bool = false
        var siteURL: String = ""
        var otherIDs: [DocID] = []
        var notes: [String] = []
        var source: ItemSource = ItemSource.custom
        var reminderLeadHours: Int = 2
        var reminders: [ReminderItem] = []
        var remindersCustomized: Bool = false

        init(title: String, category: ItemCategory) {
            self.title = title
            self.category = category
        }
    }
}

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
            let legacy = try ModelContainer(
                for: Schema(versionedSchema: BuildTwoSchema.self),
                configurations: ModelConfiguration(
                    schema: Schema(versionedSchema: BuildTwoSchema.self), url: url))
            let context = ModelContext(legacy)
            let item = BuildTwoSchema.ActionItem(title: "Electric bill", category: .utility)
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
