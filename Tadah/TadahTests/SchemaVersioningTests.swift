//  SchemaVersioningTests.swift
//
//  Proves the versioned container (TadahSchemaV1 + TadahMigrationPlan) opens a
//  store created the OLD unversioned way — i.e. what every tester's device has
//  on disk — without losing data. If this test ever fails, DO NOT ship the
//  container change: the resilient fallback would wipe tester data on update.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

struct SchemaVersioningTests {

    @MainActor
    @Test func versionedContainerOpensLegacyStoreWithDataIntact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }

        // 1) Create + fill a store exactly the way shipped builds did:
        //    a plain, UNversioned ModelContainer.
        do {
            let legacy = try ModelContainer(
                for: ActionItem.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(legacy)
            let item = ActionItem(title: "Electric bill", category: .utility,
                                  amount: Decimal(string: "42.17"),
                                  dueDate: .now.addingTimeInterval(86400),
                                  steps: [ChecklistStep(text: "Pay it")])
            item.notes = ["June statement"]
            context.insert(item)
            try context.save()
        }

        // 2) Reopen the SAME file the way the app now does (versioned + plan).
        let versioned = try TadahApp.versionedContainer(url: url)
        let fetched = try ModelContext(versioned).fetch(FetchDescriptor<ActionItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Electric bill")
        #expect(fetched.first?.amount == Decimal(string: "42.17"))
        #expect(fetched.first?.steps.count == 1)
        #expect(fetched.first?.notes == ["June statement"])
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
