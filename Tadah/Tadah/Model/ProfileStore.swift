//  ProfileStore.swift
//
//  Owns the family's profiles and which one you're currently looking at.
//
//  Two separate ideas, deliberately not the same thing:
//
//   • `me` — WHO IS USING THIS PHONE. Persists per device (UserDefaults), and is
//     the default person a new to-do is filed under. Mom's phone says Mom.
//   • `scope` — WHAT YOU'RE LOOKING AT: the whole family (the default) or just
//     your own. Also per device; syncing a view filter between phones would
//     fight the user.
//
//  A to-do with no person (profileID == nil) is FOR THE FAMILY — a shared
//  errand, not an orphan. Those show up in everyone's "just mine" view too,
//  because they're everyone's.
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
    private static let scopeKey = "tadah.inboxScope"
    private let defaults: UserDefaults

    // Cached list: owner first, then by creation order — the order the avatar
    // strip renders in.
    private(set) var profiles: [Profile] = []
    private(set) var activeID: UUID?
    // What the Inbox shows. Everyone by default: the reason to add family members
    // is to see what's due across the family in one place, so making people
    // switch profiles to find that out defeats the feature.
    var scope: Scope = .everyone {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeKey) }
    }

    enum Scope: String { case everyone, mine }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.activeKey) { activeID = UUID(uuidString: raw) }
        if let raw = defaults.string(forKey: Self.scopeKey), let s = Scope(rawValue: raw) { scope = s }
    }

    var owner: Profile? { profiles.first { $0.isOwner } ?? profiles.first }
    // Who's using this phone. Falls back to the owner.
    var me: Profile? { profiles.first { $0.id == activeID } ?? owner }
    var activeProfileID: UUID? { me?.id }
    var hasFamily: Bool { profiles.count > 1 }

    // Does this item belong in the current view? Family items (no person) are
    // everyone's, so they show in both scopes.
    func isVisible(profileID: UUID?) -> Bool {
        switch scope {
        case .everyone: return true
        case .mine:     return profileID == nil || profileID == activeProfileID
        }
    }

    // The person a given item is filed under, or nil when it's a family to-do.
    func profile(for id: UUID?) -> Profile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

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
