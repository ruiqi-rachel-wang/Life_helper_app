//  ProfileStore.swift
//
//  Owns the family's profiles and which one you're currently looking at.
//
//  Two separate ideas, deliberately not the same thing:
//
//   • `me` — WHO IS USING THIS PHONE. Persists per device (UserDefaults). Mom's
//     phone says Mom. Read it through `activeProfileID`, never directly: that is
//     the one that also honours the subscription lock, and it is what decides the
//     person a new to-do is filed under.
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
    // Marks that the one-time "items from before profiles existed become the
    // owner's" backfill has run. See adoptPreProfileItemsOnce — after this, a nil
    // profileID means "Everyone", not "not yet migrated".
    static let didBackfillKey = "tadah.didBackfillPreProfileItems"
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
    // WHO NEW TO-DOS ARE FILED UNDER, and the person the switcher ticks.
    //
    // Falls back to the OWNER whenever the family is locked. `activeID` outlives a
    // lock — it's a persisted device setting, and locking deliberately hides
    // profiles without deleting anything — so someone whose Plus lapsed while
    // viewing Mum kept filing every new to-do under Mum, on a screen showing one
    // plain list with no switcher and no assignee picker to see it or change it.
    // Those items then reappeared under Mum on resubscribing, and the free item
    // cap was being counted against Mum's bucket rather than the visible list.
    //
    // Same rule as `isVisible` and `reminderMinutes`: locked means the app behaves
    // as if there were exactly one person, the account owner.
    var activeProfileID: UUID? { familyUnlocked ? me?.id : owner?.id }
    // Is the family feature currently PAID FOR? Kept in sync with PlusStore by
    // TadahApp. Defaults to true so nothing is hidden before RevenueCat has
    // answered — a subscriber must never watch their family disappear at launch.
    //
    // ⚠️ THIS HIDES, IT NEVER DELETES. A lapsed subscription is usually a expired
    // card, not a decision, and it is very often temporary. Profiles and every
    // item's `profileID` stay exactly as they are, so resubscribing restores the
    // whole arrangement instead of asking someone to rebuild their family and
    // refile a hundred to-dos.
    var familyUnlocked = true

    // ONE gate for the entire family feature. Every screen already asks this
    // question, so putting the subscription check here — rather than adding
    // `plus.isPlus &&` at each call site — means no screen can be forgotten.
    var hasFamily: Bool { familyUnlocked && profiles.count > 1 }

    // Does this item belong in the current view? Family items (no person) are
    // everyone's, so they show in both scopes.
    func isVisible(profileID: UUID?) -> Bool {
        // A LAPSED SUBSCRIPTION MUST NEVER HIDE A TO-DO. Without this, someone
        // whose Plus ended while viewing "just mine" as Mum would lose the family
        // switcher (hasFamily is false now) with the filter still applied — their
        // own to-dos would look deleted, and there'd be no control left to get
        // them back. Locked means one plain list containing everything.
        guard familyUnlocked else { return true }
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

    // What time of day a to-do filed under `id` should remind, in minutes past
    // midnight. Falls back to the device default when this person hasn't set one
    // — and for family to-dos (nil), which belong to nobody in particular.
    //
    // Also falls back when the family is LOCKED: a lapsed subscription shouldn't
    // quietly keep applying per-person times the user can no longer see or change.
    func reminderMinutes(for id: UUID?) -> Int {
        guard familyUnlocked, let mins = profile(for: id)?.reminderMinutes else {
            return AppSettings.defaultReminderMinutes
        }
        return mins
    }

    // MARK: - loading

    // Throwing sibling of `reload`, for safety-critical callers (bindOwner). A
    // failed read here must propagate, never be mistaken for an empty account.
    func reloadThrowing(_ context: ModelContext) throws {
        let fetched = try context.fetch(FetchDescriptor<Profile>())
        profiles = fetched.sorted {
            if $0.isOwner != $1.isOwner { return $0.isOwner }
            return $0.createdAt < $1.createdAt
        }
        if activeID == nil || !profiles.contains(where: { $0.id == activeID }) {
            setActive(owner?.id)
        }
    }

    func reload(_ context: ModelContext) {
        // A failed read must NOT be turned into "this account has no profiles".
        // Callers use `profiles` to decide who the owner is and whether a family
        // exists, so an empty cache reads as "no owner" and invites creating a
        // duplicate. Keep the last good list instead.
        guard let fetched = try? context.fetch(FetchDescriptor<Profile>()) else { return }
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
    // testers upgrading from a build without profiles). Idempotent — safe on every
    // launch.
    @discardableResult
    func ensureOwnerProfile(_ context: ModelContext, name: String) -> Profile {
        reload(context)
        sweepDiscardableProfiles(context)
        if let existing = owner {
            // Filling a blank owner name is a real edit, so it has to be stamped —
            // otherwise the repair stays on this device forever and every other
            // device keeps showing "Unnamed".
            if existing.name.isEmpty, !name.isEmpty {
                existing.name = name
                existing.touch()
            }
            adoptPreProfileItemsOnce(context, into: existing)
            resolveDuplicateColors(context)
            return existing
        }
        let created = Profile(name: name, colorIndex: 0, isOwner: true)
        context.insert(created)
        adoptPreProfileItemsOnce(context, into: created)
        reload(context)
        return created
    }

    // Bind this device's owner profile to the account that just signed in, and
    // collapse any duplicate owners.
    //
    // The owner profile is created before anyone signs in, with a random id. Left
    // alone, every device that signs into the same account pushes its OWN owner —
    // three devices, three "owners" — and an owner profile left over from account A
    // gets pushed into account B under A's name. Re-keying to the account-derived
    // id (see Profile.ownerID) makes every device agree on one id, and makes A's
    // leftover owner un-adoptable by B.
    //
    // Call on sign-in, before the first sync.
    // `previousAccountOverride` exists for tests, which must not write to the
    // shared UserDefaults that LocalDataOwner reads. nil = ask LocalDataOwner.
    func bindOwner(to userID: String,
                   name: String = "",
                   in context: ModelContext,
                   previousAccountOverride: String? = nil) throws {
        // THROWING read, not `reload`.
        //
        // reload() deliberately keeps its last good list when a fetch fails —
        // right for UI refreshes, wrong here. With an empty cache that failure
        // looked like "this account has no profiles at all", so bindOwner fell
        // through its guard and reported SUCCESS having bound nothing. The
        // caller's do/catch could never see it, and sign-in proceeded to sync an
        // unmigrated identity.
        try reloadThrowing(context)
        let canonical = Profile.ownerID(forAccount: userID)
        let owners = profiles.filter { $0.isOwner }

        // Does the owner profile on this device belong to a DIFFERENT account?
        //
        // If so it must NOT be re-keyed. Re-keying moves the existing profile's
        // NAME onto the new account's owner id — so signing in as B on a phone that
        // had been A's would have produced an owner for B literally called "Ana".
        // One person's name silently becomes another person's account holder.
        // Demote and start a fresh owner instead; A's profile is kept intact under
        // its own id, because it may still hold their to-dos.
        let previousAccount = previousAccountOverride ?? LocalDataOwner.current()
        let ownerBelongsToAnotherAccount = previousAccount != nil && previousAccount != userID

        if ownerBelongsToAnotherAccount {
            for existing in owners {
                // Demoting is only worth doing when the profile carries something
                // a person would miss — their name, or their to-dos. An owner that
                // has NEITHER is an artifact of this device's setup, and keeping it
                // leaves a second "Unnamed" face in the switcher that the user
                // never created and cannot explain. On a free account (cap 1) it
                // also silently consumes the single allowed profile. Retire it.
                if try isDiscardable(existing, in: context) {
                    context.insert(ProfileTombstone(id: existing.id))
                    context.delete(existing)
                    continue
                }
                existing.isOwner = false
                existing.touch()
            }
            try reloadThrowing(context)
            if let mine = profiles.first(where: { $0.id == canonical }) {
                mine.isOwner = true
                mine.touch()
            } else {
                let fresh = Profile(name: name, colorIndex: 0, isOwner: true, id: canonical)
                context.insert(fresh)
            }
            setActive(canonical)
            reload(context)
            return
        }

        // Keep the canonical one if it already exists, else the oldest.
        let keeper = owners.first { $0.id == canonical }
            ?? owners.min { $0.createdAt < $1.createdAt }

        // NO OWNER AT ALL is a real, reachable state — not a reason to give up.
        // "Use the account's tasks" deletes every profile on the device and then
        // calls this, so returning here left the account with no owner and every
        // task orphaned. A successful-but-empty read means: create the canonical
        // owner.
        guard let keeper else {
            let fresh = Profile(name: name, colorIndex: 0, isOwner: true, id: canonical)
            context.insert(fresh)
            setActive(canonical)
            try reloadThrowing(context)
            return
        }

        // Any OTHER owner is a duplicate from another device. Demote rather than
        // delete: it may carry a real person's name and to-dos. If it carries
        // neither, it is not a person — retire it (see isDiscardable).
        for extra in owners where extra.id != keeper.id {
            if try isDiscardable(extra, in: context) {
                context.insert(ProfileTombstone(id: extra.id))
                context.delete(extra)
                continue
            }
            extra.isOwner = false
            extra.touch()
        }

        if keeper.id != canonical {
            let old = keeper.id
            // Already migrated on another device? Then the canonical profile is
            // already here — adopt it and retire the local random one instead of
            // inserting a second copy under an id that exists.
            let alreadyCanonical = profiles.first { $0.id == canonical }

            // THROWING. `try? … ?? []` here meant a failed fetch looked like "the
            // old owner has no to-dos" — and the migration then deleted and
            // tombstoned that profile anyway, orphaning every item still pointing
            // at it. Nothing may be deleted until its children have been read.
            let items = try context.fetch(FetchDescriptor<ActionItem>(
                predicate: #Predicate { $0.profileID == old }))

            if alreadyCanonical == nil {
                let replacement = Profile(name: keeper.name, colorIndex: keeper.colorIndex,
                                          isOwner: true, id: canonical)
                replacement.createdAt = keeper.createdAt
                context.insert(replacement)
            } else {
                alreadyCanonical?.isOwner = true
                alreadyCanonical?.touch()
            }

            for item in items {
                item.profileID = canonical
                item.touch()          // so the re-pointing actually syncs
            }
            if activeID == old { setActive(canonical) }

            // TOMBSTONE the old id. Without this the random-keyed owner lives on in
            // the account: the server keeps counting it, so a free account is seen
            // as having two profiles and rejects the canonical owner with a 409
            // profile_limit — and other devices keep pulling a ghost owner back.
            // Deleting locally is not enough; the deletion has to travel.
            context.insert(ProfileTombstone(id: old))
            context.delete(keeper)
        }
        reload(context)
    }

    // Clears up leftovers an EARLIER build already wrote to disk.
    //
    // Before `isDiscardable` existed, signing into a different account demoted the
    // old owner and kept it forever. On a device that had never named its owner
    // that left a nameless, empty second profile — a stranger's face in the
    // switcher that the user never added, and, on a free account (cap 1), one that
    // used up their only profile slot. The code path is fixed, but devices that
    // already ran it need the leftover removed.
    //
    // Deliberately conservative: never the owner, never a named profile, never one
    // holding to-dos, and never the last profile standing. A read failure skips the
    // sweep entirely rather than guessing.
    private func sweepDiscardableProfiles(_ context: ModelContext) {
        guard profiles.count > 1 else { return }
        var removed = false
        for profile in profiles where !profile.isOwner {
            guard profiles.count - (removed ? 1 : 0) > 1 else { break }
            guard let discardable = try? isDiscardable(profile, in: context), discardable else { continue }
            context.insert(ProfileTombstone(id: profile.id))   // so it goes on other devices too
            context.delete(profile)
            removed = true
        }
        if removed { reload(context) }
    }

    // Can this profile be thrown away without losing anything a person would miss?
    //
    // Only when it has no name AND no to-dos. Both conditions matter: a named
    // profile is somebody, even if empty; a profile holding to-dos is somebody's
    // list, even if unnamed. THROWS rather than treating a failed read as "no
    // items" — that mistake would delete a real person's list.
    private func isDiscardable(_ profile: Profile, in context: ModelContext) throws -> Bool {
        guard profile.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let pid = profile.id
        let items = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.profileID == pid }))
        return items.isEmpty
    }

    // ONE-TIME upgrade step, and it must stay one-time.
    //
    // Items saved before profiles existed have profileID == nil, and on the upgrade
    // they should become the owner's so nothing disappears. But `nil` has since
    // taken on a SECOND meaning: a to-do filed under "Everyone" — a shared family
    // errand. Re-running this on every launch therefore quietly reassigned every
    // family to-do to the owner, so "Everyone" never survived a relaunch.
    //
    // The flag is what separates the two meanings: before it is set, nil means
    // "predates profiles"; after, nil means "Everyone". Keyed in UserDefaults
    // rather than inferred, because once the backfill has run the two cases are
    // indistinguishable by looking at the data.
    private func adoptPreProfileItemsOnce(_ context: ModelContext, into profile: Profile) {
        guard !defaults.bool(forKey: Self.didBackfillKey) else { return }
        // If the read fails, DON'T set the flag — retry on the next launch. Marking
        // it done on a failed fetch would permanently skip the one chance these
        // pre-profile items get to be adopted onto the owner.
        guard let orphans = try? context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.profileID == nil })) else { return }
        for item in orphans { item.profileID = profile.id }
        defaults.set(true, forKey: Self.didBackfillKey)
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
        let created = Profile(name: name, colorIndex: freeColorIndex())
        context.insert(created)
        reload(context)
        return created
    }

    // The lowest palette slot nobody is using.
    //
    // This was `profiles.count % paletteCount`, which collides as soon as the
    // count stops matching the slots in use: owner(0) + A(1) + B(2), remove A,
    // add C — count is 2, so C is handed slot 2, the colour B already has. Two
    // family members then look identical in the switcher, which is the one job
    // the colour has. Past six profiles (the cap is eight) reuse is unavoidable,
    // so fall back to the least-used slot rather than always the same one.
    private func freeColorIndex() -> Int {
        var used: [Int: Int] = [:]
        for p in profiles {
            let slot = ((p.colorIndex % Profile.paletteCount) + Profile.paletteCount) % Profile.paletteCount
            used[slot, default: 0] += 1
        }
        if let free = (0..<Profile.paletteCount).first(where: { used[$0] == nil }) { return free }
        return (0..<Profile.paletteCount).min { (used[$0] ?? 0) < (used[$1] ?? 0) } ?? 0
    }

    // Repair profiles that ALREADY share a colour, from the buggy assignment
    // above or from a sync that landed two people on one slot. The owner keeps
    // slot 0 (it's the app's accent); everyone else moves to a free slot in
    // creation order. Stamped so the change reaches the family's other devices.
    private func resolveDuplicateColors(_ context: ModelContext) {
        var seen = Set<Int>()
        var changed = false
        for profile in profiles {
            let slot = ((profile.colorIndex % Profile.paletteCount) + Profile.paletteCount) % Profile.paletteCount
            if profile.isOwner { seen.insert(slot); continue }
            if seen.contains(slot) {
                let free = (0..<Profile.paletteCount).first { !seen.contains($0) }
                if let free, free != slot {
                    profile.colorIndex = free
                    profile.touch()
                    changed = true
                    seen.insert(free)
                    continue
                }
            }
            seen.insert(slot)
        }
        if changed { reload(context) }
    }

    // STAMPS ONLY ON A REAL CHANGE.
    //
    // It used to touch unconditionally, so opening Edit and pressing Save without
    // typing anything advanced `updatedAt` — and under last-writer-wins that stale
    // local copy then beat a genuine rename (or reminder-time change) made on
    // another device. Exactly the false-touch bug already fixed twice, in task
    // detail and step detail; the guard belongs HERE rather than at the call site
    // so every caller inherits it.
    func rename(_ profile: Profile, to name: String, in context: ModelContext) {
        guard profile.name != name else { return }
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
        // THROWING. `try? … ?? []` meant a failed read looked like "this person has
        // no to-dos", and the profile was then deleted and tombstoned anyway —
        // their items left behind with no owner, and no tombstones, so they'd
        // silently reappear merged into someone else's list on every device.
        let owned = try context.fetch(FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.profileID == pid }))
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
