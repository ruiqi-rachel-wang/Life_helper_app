//  SyncFoundationTests.swift
//
//  Phase 1 of Part 3 sync: the on-device data foundation + backup. These prove
//  the primitives are safe BEFORE any server code exists — serialization is
//  lossless (minus images by design), touch() advances the LWW clock, deletes
//  leave tombstones, and a backup snapshot restores exactly.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

struct SyncFoundationTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: ActionItem.self, TaskTombstone.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // Rich item with WHOLE-SECOND dates so the ISO-8601 (second-precision) JSON
    // round-trip compares equal.
    private func sampleItem() -> ActionItem {
        let item = ActionItem(
            title: "Electric bill", category: .utility,
            amount: Decimal(string: "42.17"), currency: "USD",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            note: "pay online",
            steps: [ChecklistStep(text: "Pay it", done: true,
                                  detail: StepDetail(explanation: "via the portal",
                                                     miniChecklist: ["log in"]))],
            recurrence: .monthly)
        item.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        item.updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        item.summary = "June bill"
        item.documentType = "Utility bill"
        item.otherIDs = [DocID(label: "Acct", value: "123")]
        item.notes = ["statement"]
        item.reminders = [ReminderItem(date: Date(timeIntervalSince1970: 1_799_000_000), note: "due soon")]
        item.remindersCustomized = true
        item.source = .scanned
        return item
    }

    @Test func taskDTORoundTripsThroughJSON() throws {
        let dto = TaskDTO(sampleItem())
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(TaskDTO.self, from: try enc.encode(dto))
        #expect(decoded == dto)
    }

    @Test func dtoOmitsImageButRebuildsEverythingElse() {
        let item = sampleItem()
        item.imageData = Data([0x1, 0x2, 0x3])
        let rebuilt = TaskDTO(item).makeItem()
        #expect(rebuilt.imageData == nil)          // images never travel in the DTO
        #expect(rebuilt.id == item.id)
        #expect(rebuilt.title == item.title)
        #expect(rebuilt.amount == item.amount)
        #expect(rebuilt.recurrence == .monthly)
        #expect(rebuilt.steps.first?.detail?.explanation == "via the portal")
        #expect(rebuilt.otherIDs == item.otherIDs)
        #expect(rebuilt.reminders == item.reminders)
    }

    @MainActor
    @Test func touchAdvancesUpdatedAt() {
        let item = sampleItem()
        item.updatedAt = .distantPast
        item.touch()
        #expect(item.updatedAt > .distantPast)
        #expect(abs(item.updatedAt.timeIntervalSinceNow) < 5)
    }

    @MainActor
    @Test func deleteLeavesTombstoneForRealItemsOnly() throws {
        let context = ModelContext(try container())
        let real = sampleItem(); context.insert(real)
        let example = ActionItem(title: "tutorial", category: .other)
        example.isExample = true; context.insert(example)
        try context.save()
        let realID = real.id

        ItemActions.delete(real, in: context)
        ItemActions.delete(example, in: context)   // example → no tombstone
        try context.save()

        let stones = try context.fetch(FetchDescriptor<TaskTombstone>())
        #expect(stones.count == 1)
        #expect(stones.first?.id == realID)
        #expect(try context.fetch(FetchDescriptor<ActionItem>()).isEmpty)
    }

    @MainActor
    @Test func snapshotThenRestoreReplacesLocalData() throws {
        // Source store: one real item + one tombstone.
        let source = ModelContext(try container())
        let item = sampleItem(); item.imageData = Data([0xAA]); source.insert(item)
        source.insert(TaskTombstone(id: UUID()))
        try source.save()

        let url = try TaskBackup.snapshot(from: source)
        defer { try? FileManager.default.removeItem(at: url) }

        // Restore into a DIFFERENT store that already holds stale data.
        let target = ModelContext(try container())
        target.insert(ActionItem(title: "stale — should be gone", category: .other))
        try target.save()

        try TaskBackup.restore(from: url, into: target)
        try target.save()

        let items = try target.fetch(FetchDescriptor<ActionItem>())
        #expect(items.count == 1)
        #expect(items.first?.title == "Electric bill")
        #expect(items.first?.imageData == nil)   // image not carried, not clobbered either
        #expect(try target.fetch(FetchDescriptor<TaskTombstone>()).count == 1)
    }
}
