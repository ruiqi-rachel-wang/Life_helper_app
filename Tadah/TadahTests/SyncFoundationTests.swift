//  SyncFoundationTests.swift
//
//  Phase 1 of Part 3 sync: the on-device data foundation. These prove the
//  primitives are safe BEFORE any server code exists — serialization is lossless
//  (minus images by design), touch() advances the LWW clock, and deletes leave
//  tombstones.
//
//  The snapshot/restore test that lived here went with TaskBackup (2026-08-13):
//  once reconciliation became non-destructive, nothing in the app deletes a
//  user's to-dos on their behalf, so there was no destructive step left for a
//  local backup to guard.
//

import Testing
import Foundation
import SwiftData
@testable import Tadah

// @MainActor because TaskDTO's Codable/Equatable conformances are main-actor
// isolated (it's built from the @Model ActionItem). Calling them from a
// nonisolated test is a warning today and an ERROR under the Swift 6 language
// mode — this is the same annotation the other sync test suites already carry.
@MainActor
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

    // THE CONTRACT DETAIL/STEP-DETAIL CHANGE DETECTION RESTS ON.
    //
    // Those screens snapshot `TaskDTO(item)` when editing opens and stamp
    // `updatedAt` on the way out ONLY if the value differs. That is what keeps
    // merely READING a to-do from bumping its timestamp and overwriting a real
    // edit from another device under last-writer-wins — while still catching an
    // edit the user never confirmed with "Done".
    //
    // So the DTO has to notice every editable field. If one is ever dropped from
    // TaskDTO, edits to it would silently stop syncing again, and nothing else
    // would fail. This is that alarm.
    @Test func taskDTOEqualityNoticesEveryEditableField() {
        func changed(_ mutate: (ActionItem) -> Void) -> Bool {
            let item = sampleItem()
            let before = TaskDTO(item)
            mutate(item)
            return TaskDTO(item) != before
        }

        #expect(changed { $0.title = "Water bill" })
        #expect(changed { $0.note = "pay by post" })
        #expect(changed { $0.amount = Decimal(string: "9.99") })
        #expect(changed { $0.currency = "EUR" })
        #expect(changed { $0.dueDate = Date(timeIntervalSince1970: 1_900_000_000) })
        #expect(changed { $0.dueHasTime.toggle() })
        #expect(changed { $0.category = .medical })
        #expect(changed { $0.status = .done })
        #expect(changed { $0.summary = "July bill" })
        #expect(changed { $0.documentType = "Bank letter" })
        #expect(changed { $0.sender = "Utility Co" })
        #expect(changed { $0.siteURL = "https://example.com" })
        #expect(changed { $0.notes = ["something else"] })
        #expect(changed { $0.otherIDs = [DocID(label: "Ref", value: "999")] })
        #expect(changed { $0.reminders = [] })
        #expect(changed { $0.remindersCustomized.toggle() })
        #expect(changed { $0.reminderLeadHours = 48 })
        #expect(changed { $0.profileID = UUID() })
        // Recurrence is edited in Detail (the "Repeats" row) and its two companion
        // fields travel with it. Missing from the first version of this test.
        #expect(changed { $0.recurrence = .weekly })
        #expect(changed { $0.recurrence = nil })
        #expect(changed { $0.seriesID = UUID() })
        #expect(changed { $0.recurrenceAnchorDay = 15 })
        #expect(changed { $0.senderShort = "UtilCo" })

        // Steps, including the nested detail the Step Detail sheet edits — the
        // whole reason that sheet reports changes at all.
        #expect(changed { $0.steps[0].text = "Pay it today" })
        #expect(changed { $0.steps[0].done.toggle() })
        #expect(changed { $0.steps[0].detail?.explanation = "call them instead" })
        #expect(changed { $0.steps[0].detail?.miniChecklist[0].done.toggle() })
        #expect(changed { $0.steps[0].detail?.miniChecklist.append(SubStep(text: "new")) })

        // And the other half of the contract: an untouched item must compare EQUAL,
        // or every read would stamp and we'd be back to overwriting live edits.
        #expect(!changed { _ in })
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

}
