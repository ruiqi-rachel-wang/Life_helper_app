//  PhotoStash.swift
//
//  Scanned photos, kept on the device across a sign-out.
//
//  WHY THIS EXISTS: a photo lives in `ActionItem.imageData`
//  (@Attribute(.externalStorage)), so it dies with the row. Sign-out now deletes
//  the account's to-dos from the device — they live in the account and come back
//  on the next sign-in — but photos are NOT uploaded (the privacy policy promises
//  that in six places), so deleting the row would destroy the only copy of the
//  original document, permanently, with no way to get it back.
//
//  So the photo is moved aside before the row goes, filed under the item's id,
//  and re-attached when that item is pulled back down. Same phone only: this is
//  a local cache, not a backup. Sign in on a different device and the to-do
//  arrives without its picture, exactly as the policy says.
//
//  Stored in Application Support (not Caches — the system may evict Caches under
//  pressure, and a silently-vanished document photo is the failure this exists to
//  prevent) and excluded from iCloud/iTunes backup, which matches where the
//  SwiftData store the photo came from already sits.
//

import Foundation

enum PhotoStash {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("KeptPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var url = dir
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
            } catch { return nil }
        }
        return dir
    }

    private static func file(_ itemID: UUID) -> URL? {
        directory?.appendingPathComponent("\(itemID.uuidString).photo")
    }

    // Set aside one item's photo. No-op when the item has none, so callers can
    // hand over every item without checking first.
    static func keep(_ data: Data?, for itemID: UUID) {
        guard let data, !data.isEmpty, let url = file(itemID) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // The photo for an item, if this device still holds one.
    static func photo(for itemID: UUID) -> Data? {
        guard let url = file(itemID), let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return data
    }

    // Called once the photo is back on the item, so the same bytes aren't kept
    // twice. Failing to remove it is harmless — it is only wasted space, and the
    // next re-attach overwrites it.
    static func drop(_ itemID: UUID) {
        guard let url = file(itemID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // Everything this device is holding. Used by the tests, and by any future
    // "free up space" affordance.
    static func keptCount() -> Int {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        return names.filter { $0.hasSuffix(".photo") }.count
    }

    // Drop the lot. For a real erase — deleting the account, or clearing data the
    // person asked to be rid of — where keeping the pictures would be the wrong
    // kind of helpful.
    static func dropAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
