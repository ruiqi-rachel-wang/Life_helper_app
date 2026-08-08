//  TadahSchema.swift
//
//  The versioned description of what's in the SwiftData store. V1 is the
//  baseline — exactly the models shipped so far, just stamped with a version.
//
//  WHY: without this, any stored-property change makes the store unopenable
//  and the resilient fallback in TadahApp WIPES tester data. With it, a
//  model change becomes a new TadahSchemaVn + a MigrationStage here (lightweight
//  or custom), and updates carry data forward instead of losing it.
//
//  V2 (Part 3 sync foundation): adds ActionItem.updatedAt (LWW basis) and the
//  new TaskTombstone model. Both are additive → a lightweight migration, so
//  existing tester items carry forward untouched.
//
//  Rule: DON'T mutate a shipped version's stored properties — add a new Vn.
//  Unit-tested: an old store opens under this plan with its data intact and a
//  V1 store migrates to V2 (see SchemaVersioningTests).
//

import Foundation
import SwiftData

// ⚠️ V1 and V2 both point at the CURRENT ActionItem type. That is a known
// weakness, not a design: `ActionItem` has since gained `updatedAt` and
// `profileID`, so "V1" no longer describes what build 2 actually shipped, and a
// test that builds its fixture from these can't prove a build-2 store migrates.
//
// The honest check is therefore NOT "does V1 round-trip" but "does a store
// written by the build-2 MODEL SHAPE open under the current plan" —
// SchemaVersioningTests does that with `LegacyV1ActionItem`, an independent
// frozen copy of the build-2 properties that this file can never accidentally
// change. Freeze future versions by copying the model, not by re-pointing here.
nonisolated enum TadahSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ActionItem.self] }
}

nonisolated enum TadahSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ActionItem.self, TaskTombstone.self] }
}

// V3 (family sharing): adds Profile + ProfileTombstone and ActionItem.profileID. Both are
// additive — profileID is optional, so existing rows migrate untouched and are
// adopted onto the owner profile at launch by ProfileStore.ensureOwnerProfile.
// (Doing the backfill in the app rather than a custom migration stage keeps the
// migration lightweight and the backfill re-runnable if it's ever interrupted.)
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

    // Additive only (new field with a default + new model) → lightweight.
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV1.self, toVersion: TadahSchemaV2.self)
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TadahSchemaV2.self, toVersion: TadahSchemaV3.self)
}
