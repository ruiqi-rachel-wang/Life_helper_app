//  CueviSchema.swift
//
//  The versioned description of what's in the SwiftData store. V1 is the
//  baseline — exactly the models shipped so far, just stamped with a version.
//
//  WHY: without this, any stored-property change makes the store unopenable
//  and the resilient fallback in CueviApp WIPES tester data. With it, a future
//  model change becomes CueviSchemaV2 + a MigrationStage here (lightweight or
//  custom), and updates carry data forward instead of losing it.
//
//  Rule stays the same until a V2 exists: DON'T change stored properties.
//  Unit-tested: a store created the old unversioned way opens under this plan
//  with its data intact (see SchemaVersioningTests).
//

import Foundation
import SwiftData

nonisolated enum CueviSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ActionItem.self] }
}

nonisolated enum CueviMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CueviSchemaV1.self] }
    // No stages yet — V1 is the only version. The first real model change adds
    // CueviSchemaV2 and a stage V1→V2 here.
    static var stages: [MigrationStage] { [] }
}
