//  ProfileStore.swift
//
//  Owns the family's profiles and which one you're currently looking at.
//
//  The ACTIVE profile is per-device (UserDefaults), deliberately: "whose list am I
//  viewing right now" is view state, not account data. Mom's phone and the
//  daughter's phone can sit on different profiles at the same time, and syncing an
//  active-profile pointer between them would fight the user.
//
//  Cap (decided 2026-08-05): Free = 1 profile, Tadah Plus = 8. Checked here for a
//  good error message; the server re-checks it, since a client can lie.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ProfileStore {
    static let freeMax = 1
    static let plusMax = 8

    static func cap(plus: Bool) -> Int { plus ? plusMax : freeMax }

    private static let activeKey = "tadah.activeProfileID"
    private let defaults: UserDefaults

    // Cached list: owner first, then by creation order — the order the avatar
    // strip renders in.
    private(set) var profiles: [Profile] = []
    private(set) var activeID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.activeKey) { activeID = UUID(uuidString: raw) }
    }

    var owner: Profile? { profiles.first { $0.isOwner } ?? profiles.first }
    var active: Profile? { profiles.first { $0.id == activeID } ?? owner }
    // The id every new item should be stamped with.
    var activeProfileID: UUID? { active?.id }
    var hasFamily: Bool { profiles.count > 1 }

    // MARK: - loading

    func reload(_ context: ModelContext) {
        let fetched = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        profiles = fetched.sorted {
            if $0.isOwner != $1.isOwner { return $0.isOwner }
            return $0.createdAt < $1.createdAt
        }
        // An active id pointing at a deleted profile falls back to the owner.
        if activeID == nil || !profiles.contains(where: { $0.id == activeID }) {
            setActive(owner?.id)
        }
    }

    // Every account has exactly one owner profile. Creates it on first run (and for
    // testers upgrading from a build without profiles) and adopts any pre-profile
    // items. Idempotent — safe on every launch.
    @discardableResult
    func ensureOwnerProfile(_ context: ModelContext, name: String) -> Profile {
        reload(context)
        if let existing = owner {
            if existing.name.isEmpty, !name.isEmpty { existing.name = name }
            adoptOrphanItems(context, into: existing)
            return existing
        }
        let created = Profile(name: name, colorIndex: 0, isOwner: true)
        context.insert(created)
        adoptOrphanItems(context, into: created)
        reload(context)
        return created
    }

    // Items saved before profiles existed have profileID == nil. Stamp them onto
    // the owner so nothing becomes invisible after the upgrade. Examples included —
    // the tutorial items should show up on the owner's list like they always did.
    private func adoptOrphanItems(_ context: ModelContext, into profile: Profile) {
        let orphans = (try? context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.profileID == nil }))) ?? []
        for item in orphans { item.profileID = profile.id }
    }

    // MARK: - switching

    func setActive(_ id: UUID?) {
        activeID = id
        if let id { defaults.set(id.uuidString, forKey: Self.activeKey) }
        else { defaults.removeObject(forKey: Self.activeKey) }
    }

    // MARK: - CRUD

    enum ProfileError: Error, Equatable {
        case capReached(Int)      // how many this tier allows
        case cannotDeleteOwner
    }

    @discardableResult
    func add(name: String, plus: Bool, in context: ModelContext) throws -> Profile {
        reload(context)
        let limit = Self.cap(plus: plus)
        guard profiles.count < limit else { throw ProfileError.capReached(limit) }
        let created = Profile(name: name,
                              colorIndex: profiles.count % Profile.paletteCount)
        context.insert(created)
        reload(context)
        return created
    }

    func rename(_ profile: Profile, to name: String, in context: ModelContext) {
        profile.name = name
        profile.touch()
        reload(context)
    }

    // Removing a family member takes their to-dos with them — those belong to that
    // person, and leaving them behind would silently merge Mom's bills into the
    // owner's list. Goes through ItemActions.delete so each one leaves a tombstone
    // and the deletion reaches the family's other devices. The owner can't be removed.
    func delete(_ profile: Profile, in context: ModelContext) throws {
        guard !profile.isOwner else { throw ProfileError.cannotDeleteOwner }
        let pid = profile.id
        let owned = (try? context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.profileID == pid }))) ?? []
        for item in owned { ItemActions.delete(item, in: context) }
        context.insert(ProfileTombstone(id: pid))   // so the removal syncs
        context.delete(profile)
        reload(context)
    }

    // A user-facing reason when another profile can't be added, else nil.
    func blockedReason(plus: Bool) -> String? {
        let limit = Self.cap(plus: plus)
        guard profiles.count >= limit else { return nil }
        return plus
            ? String(localized: "You've reached the limit of \(limit) profiles on this account.")
            : String(localized: "Family profiles are part of Tadah Plus. Upgrade to add someone like a parent to your account.")
    }
}
