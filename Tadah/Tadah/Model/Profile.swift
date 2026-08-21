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
//  (decided 2026-08-07); per-member logins are in notes/later_ideas.md.
//
//  Caps (decided 2026-08-05): Free = 1 profile, Tadah Plus = 8. Profiles and
//  devices are counted independently — any profile can be open on any device.
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class Profile {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    // Index into the avatar palette — lets each family member read at a glance.
    var colorIndex: Int = 0
    // The account holder's own profile. Exactly one exists; it can't be deleted.
    var isOwner: Bool = false
    var createdAt: Date = Date.now
    // What time of day THIS person's plain-date reminders fire, in minutes past
    // midnight. `nil` means "use the device default" — Mum can be reminded at 9am
    // while you're reminded at 7pm, without either having to be set.
    //
    // Optional with a nil default so the SwiftData migration is additive: existing
    // profiles simply keep following the device setting (see TadahSchema).
    var reminderMinutes: Int? = nil
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
        if !trimmed.isEmpty { return trimmed }
        // An OWNER with no name yet is simply the person holding the phone, so
        // "You" beats "Unnamed" — it's true, and it's friendlier than being told
        // the app doesn't know who you are. This is reachable on a first sign-in,
        // where the Apple display name arrives a launch after the profile is
        // created (see later_ideas §8f).
        return String(localized: isOwner ? "You" : "Unnamed")
    }

    // Avatar colours are picked round-robin as profiles are added. This model stays
    // UI-free — the index maps to a real Color in the theme layer.
    static let paletteCount = 6

    // MARK: - the owner's identity

    // The owner profile's id is DERIVED FROM THE ACCOUNT, not random.
    //
    // WHY: an owner profile is created on every install, before any sign-in or
    // pull. When those ids were random, every device that signed into the same
    // account pushed a *different* owner profile — so a family of three ended up
    // with three "owners", and an owner profile left behind by account A could be
    // pushed straight into account B. Deriving the id from the Apple user id makes
    // every device compute the SAME id for the same account, so pushes converge
    // instead of multiplying, and B can never adopt A's owner because the derived
    // ids differ.
    //
    // RFC 4122 §4.3 name-based UUID (v5-style: SHA-1 of namespace + name, with the
    // version/variant bits set). The namespace is arbitrary but fixed forever —
    // changing it would re-key every existing owner profile.
    static func ownerID(forAccount userID: String) -> UUID {
        let namespace = UUID(uuidString: "6E3F1B0A-9C1D-4E7A-9B2C-0F5A8D3E7C41")!
        var bytes = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        bytes.append(Data(userID.utf8))

        var digest = Insecure.SHA1.hash(data: bytes).map { $0 }
        digest[6] = (digest[6] & 0x0F) | 0x50      // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80      // RFC 4122 variant
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }
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
    // Travels with the profile so a person's reminder time follows them to every
    // device on the account, rather than being re-set on each one.
    var reminderMinutes: Int?

    init(_ p: Profile) {
        id = p.id; name = p.name; colorIndex = p.colorIndex
        isOwner = p.isOwner; createdAt = p.createdAt; updatedAt = p.updatedAt
        reminderMinutes = p.reminderMinutes
    }

    func makeProfile() -> Profile {
        let p = Profile(name: name, colorIndex: colorIndex, isOwner: isOwner, id: id)
        p.createdAt = createdAt
        p.updatedAt = updatedAt
        p.reminderMinutes = reminderMinutes
        return p
    }

    func apply(to p: Profile) {
        p.name = name; p.colorIndex = colorIndex; p.isOwner = isOwner
        p.createdAt = createdAt; p.updatedAt = updatedAt
        p.reminderMinutes = reminderMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, colorIndex, isOwner, createdAt, updatedAt, reminderMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        // Absent on payloads written before per-person reminders existed — nil is
        // exactly right there: follow the device default, as those profiles did.
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
    }
}

// See SyncService.decodeAll — the wire envelope's id/updatedAt are authoritative.
extension ProfileDTO: SyncEnvelopeBacked {}
