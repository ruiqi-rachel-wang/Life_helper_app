//  TadahSchema.swift
//
//  The versioned description of what's in the SwiftData store, and the plan that
//  carries an older store forward.
//
//  WHY: without this, a stored-property change makes the store unopenable. The app
//  no longer deletes an unopenable store (TadahApp keeps the file and runs in
//  memory for the session), so a broken migration is now a visible failure rather
//  than silent data loss — but it's still a failure. These versions are what
//  prevent it.
//
//  ⚠️ THE RULE THAT WAS BROKEN, AND WHY IT MATTERS
//  A VersionedSchema must describe the models AS THEY WERE at that version —
//  frozen, forever. V1 and V2 used to point at the live `ActionItem` type, so when
//  `ActionItem` gained `updatedAt` and `profileID`, "V1" silently changed to mean
//  something build 2 never wrote. SwiftData then could not match a real build-2
//  store to ANY declared version and refused to open it (loadIssueModelContainer)
//  — i.e. every existing tester's to-dos would have failed to load on update.
//
//  So each historical version nests its OWN frozen copy of the models. Nesting is
//  what keeps the SwiftData entity name ("ActionItem") identical across versions
//  while the Swift types stay distinct. Only the CURRENT version points at the
//  live top-level types.
//
//  Adding a version: copy the current models into a new frozen VnSchema for the
//  OLD shape if needed, point the newest version at the live types, and append a
//  stage. Never edit a shipped version's properties.
//
//  Proven by SchemaVersioningTests, which writes a store with the V1 shape and
//  reopens it through this plan.
//

import Foundation
import SwiftData

// ── V1 — what build 2 shipped. FROZEN. Do not add properties here, ever. ──────
nonisolated enum TadahSchemaV1: VersionedSchema {
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

        init(title: String = "", category: ItemCategory = .other) {
            self.title = title
            self.category = category
        }
    }
}

// ── V2 — sync foundation: ActionItem.updatedAt + TaskTombstone. FROZEN. ───────
nonisolated enum TadahSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ActionItem.self, TaskTombstone.self] }

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
        var updatedAt: Date = Date.now          // new in V2 (last-writer-wins basis)
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

        init(title: String = "", category: ItemCategory = .other) {
            self.title = title
            self.category = category
        }
    }

    @Model
    final class TaskTombstone {
        var id: UUID = UUID()
        var deletedAt: Date = Date.now

        init(id: UUID = UUID(), deletedAt: Date = .now) {
            self.id = id
            self.deletedAt = deletedAt
        }
    }
}

// ── V3 — CURRENT. Family sharing: Profile + ProfileTombstone and
// ActionItem.profileID. This version alone points at the LIVE types, so it tracks
// the app automatically. The moment a V4 is needed, freeze a copy of these here
// exactly as V1/V2 above and let V4 take over the live types.
//
// profileID is optional, so existing rows migrate untouched and are adopted onto
// the owner profile at launch by ProfileStore.ensureOwnerProfile. (Doing the
// backfill in the app rather than a custom migration stage keeps the migration
// lightweight and the backfill re-runnable if it's ever interrupted.)
nonisolated enum TadahSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self]
    }
}

nonisolated enum TadahMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TadahSchemaV1.self, TadahSchemaV2.self, TadahSchemaV3.self]
    }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    // Additive only (new fields with defaults + new models) → lightweight.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV1.self, toVersion: TadahSchemaV2.self)
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV2.self, toVersion: TadahSchemaV3.self)
}
