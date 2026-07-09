//  SchemaVersioningTests.swift
//
//  Proves the versioned container (CueviSchemaV1 + CueviMigrationPlan) opens a
//  store created the OLD unversioned way — i.e. what every tester's device has
//  on disk — without losing data. If this test ever fails, DO NOT ship the
//  container change: the resilient fallback would wipe tester data on update.
//

import Testing
import Foundation
import SwiftData
@testable import Cuevi

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
        let versioned = try CueviApp.versionedContainer(url: url)
        let fetched = try ModelContext(versioned).fetch(FetchDescriptor<ActionItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Electric bill")
        #expect(fetched.first?.amount == Decimal(string: "42.17"))
        #expect(fetched.first?.steps.count == 1)
        #expect(fetched.first?.notes == ["June statement"])
    }
}
