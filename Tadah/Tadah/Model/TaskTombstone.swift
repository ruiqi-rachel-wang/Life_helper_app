//  TaskTombstone.swift
//
//  A record that an item was deleted, kept so the deletion can propagate to the
//  account / other devices (Part 3 sync). SwiftData hard-delete removes the
//  ActionItem and its id, so without a tombstone a delete on one device would be
//  undone the next time that device pulls the still-present row from the server.
//
//  Written by ItemActions.delete for every real (non-example) item. On sync we
//  push tombstones as deletes, then purge the ones the server has acknowledged.
//  deletedAt drives both the sync cursor and (server-side) the soft-delete stamp.
//

import Foundation
import SwiftData

@Model
final class TaskTombstone {
    // The deleted item's id (same UUID the ActionItem had). Unique per item.
    @Attribute(.unique) var id: UUID = UUID()
    var deletedAt: Date = Date.now

    init(id: UUID, deletedAt: Date = .now) {
        self.id = id
        self.deletedAt = deletedAt
    }
}
