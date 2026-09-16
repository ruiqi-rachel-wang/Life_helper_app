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

// V3's ActionItem is frozen at the shipped shape. Profile is unchanged, so
// reuse its type: a duplicate nested Profile breaks SwiftData model resolution.
nonisolated enum TadahSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self]
    }
    @Model
    final class ActionItem {
        var id: UUID = UUID()
        var title: String = ""
        var category: ItemCategory = ItemCategory.other
        var amount: Decimal?
        var currency: String = "USD"
        var dueDate: Date?
        var note: String = ""
        // Photo stored as an external file (not inline in the SQLite store) so big
        // images don't bloat the database. SwiftData manages the file for us.
        @Attribute(.externalStorage) var imageData: Data?
        var status: WorkStatus = WorkStatus.todo
        var steps: [ChecklistStep] = []
        // nil = a one-off. A cadence read from the document or set by the user.
        // Marking a recurring item done spawns the next cycle; see makeNextOccurrence().
        var recurrence: Recurrence?
        // Shared across every occurrence of one recurring series, so we can keep the
        // series tidy (at most one active + one done). nil = singleton/legacy; use
        // `effectiveSeriesID`. Stamped the first time a cycle spawns.
        var seriesID: UUID?
        // The day-of-month the series should land on (e.g. 31). Captured from the
        // first occurrence's due date so month-based recurrence doesn't drift after a
        // short month (see Recurrence.nextDate). nil = no anchor (use the due day).
        var recurrenceAnchorDay: Int?
        // First-launch onboarding examples. They render normally but never schedule
        // reminders (so a tutorial item can't nag the user) and aren't real user data.
        var isExample: Bool = false
        var createdAt: Date = Date.now
        // Last time this item meaningfully changed. Basis for last-writer-wins sync
        // (Part 3, cross-device). Stamped at creation; bump with touch() on edits.
        var updatedAt: Date = Date.now
        // Which family profile this belongs to (Part 3, family sharing). Optional so
        // items saved before profiles existed stay valid — ProfileStore adopts those
        // orphans onto the owner profile at launch.
        var profileID: UUID?

        // Rich detail from AI extraction (Week 6). All optional with defaults, so
        // adding them is a lightweight SwiftData migration and manual items just
        // leave them empty. `confidence`/`lowConfidenceFields` are intentionally NOT
        // stored — they only matter at Review time (the accent underlines).
        var summary: String = ""
        var documentType: String = ""
        var sender: String = ""
        var senderShort: String = ""
        var dueHasTime: Bool = false        // dueDate carries a real time (flight/appt)
        var siteURL: String = ""
        var otherIDs: [DocID] = []          // claim/policy/confirmation numbers
        var notes: [String] = []            // side info (not action steps)
        var source: ItemSource = ItemSource.custom
        // How many hours before a TIMED event (dueHasTime) to remind — seeds the
        // default schedule (flight ~3h, appointment ~1h). Ignored for plain dates.
        var reminderLeadHours: Int = 2
        // User-customized reminders (fire-time + optional banner note). Empty +
        // !customized = use the smart defaults (defaultReminders). Once the user
        // edits, `customized` flips on and THIS list is authoritative (even if
        // emptied = no reminders).
        var reminders: [ReminderItem] = []
        var remindersCustomized: Bool = false

        init(title: String = "", category: ItemCategory = .other) {
            self.title = title
            self.category = category
        }
    }
}

// V4: persist the scan's reviewed call offer, including model-extracted phone.
nonisolated enum TadahSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ActionItem.self, TaskTombstone.self, Profile.self, ProfileTombstone.self]
    }
}

nonisolated enum TadahMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TadahSchemaV1.self, TadahSchemaV2.self, TadahSchemaV3.self, TadahSchemaV4.self]
    }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3, migrateV3toV4] }

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV3.self, toVersion: TadahSchemaV4.self)

    // Additive only (new fields with defaults + new models) → lightweight.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV1.self, toVersion: TadahSchemaV2.self)
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV2.self, toVersion: TadahSchemaV3.self)
}
