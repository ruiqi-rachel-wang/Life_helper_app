//  Profile.swift
//
//  A person-space inside ONE account (Part 3, family sharing). The daughter who
//  owns the account adds "Mom" and "Dad"; each profile has its own to-do list, so
//  Mom's bills don't mix with hers. Any family member can install Tadah, sign into
//  the SAME account (Plus allows several devices), and switch to their profile.
//
//  Deliberately NOT a second login: there is one Apple sign-in per family, so
//  there's no invite flow, no per-profile auth, and no cross-account permissions.
//  A profile is a label on data, not a security boundary — everyone signed into the
//  account can see every profile. That's the tradeoff of the shared-account model
//  (decided 2026-08-07); per-member logins are in later_ideas.md.
//
//  Caps (decided 2026-08-05): Free = 1 profile, Tadah Plus = 8. Profiles and
//  devices are counted independently — any profile can be open on any device.
//

import Foundation
import SwiftData

@Model
final class Profile {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    // Index into the avatar palette — lets each family member read at a glance.
    var colorIndex: Int = 0
    // The account holder's own profile. Exactly one exists; it can't be deleted.
    var isOwner: Bool = false
    var createdAt: Date = Date.now
    // Last meaningful change — the last-writer-wins basis when profiles sync,
    // matching ActionItem.updatedAt.
    var updatedAt: Date = Date.now

    init(name: String, colorIndex: Int = 0, isOwner: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.isOwner = isOwner
    }

    func touch() { updatedAt = .now }

    // Two-letter monogram for the avatar circle — same rule as Account.initials,
    // so the owner's circle looks identical in both places.
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "•" : letters.uppercased()
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? String(localized: "Unnamed") : trimmed
    }

    // Avatar colours are picked round-robin as profiles are added. This model stays
    // UI-free — the index maps to a real Color in the theme layer.
    static let paletteCount = 6
}

// Records that a profile was removed, so the removal reaches the family's other
// devices. Same job as TaskTombstone: a hard delete erases the id, and without
// this the next pull would resurrect the person we just removed.
@Model
final class ProfileTombstone {
    @Attribute(.unique) var id: UUID = UUID()
    var deletedAt: Date = Date.now

    init(id: UUID, deletedAt: Date = .now) {
        self.id = id
        self.deletedAt = deletedAt
    }
}

// The wire form of a Profile — what actually travels to the account. Mirrors
// TaskDTO: decoding is tolerant so an older app's payload still reads.
struct ProfileDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var colorIndex: Int
    var isOwner: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ p: Profile) {
        id = p.id; name = p.name; colorIndex = p.colorIndex
        isOwner = p.isOwner; createdAt = p.createdAt; updatedAt = p.updatedAt
    }

    func makeProfile() -> Profile {
        let p = Profile(name: name, colorIndex: colorIndex, isOwner: isOwner, id: id)
        p.createdAt = createdAt
        p.updatedAt = updatedAt
        return p
    }

    func apply(to p: Profile) {
        p.name = name; p.colorIndex = colorIndex; p.isOwner = isOwner
        p.createdAt = createdAt; p.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case id, name, colorIndex, isOwner, createdAt, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}
