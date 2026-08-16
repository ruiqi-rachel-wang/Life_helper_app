//  PasswordCrypto.swift
//
//  Turns a typed password into the value that actually travels to the Worker.
//
//  WHY THE PHONE DOES THIS AND NOT THE SERVER. Password hashing has to be slow —
//  that slowness is the entire defence against someone who steals the database
//  and starts guessing offline. A Cloudflare Worker on the free plan gets 10ms of
//  CPU per request, and PBKDF2 at a defensible iteration count needs hundreds of
//  milliseconds, so doing it server-side would either fail outright (Error 1102)
//  or have to be weakened ~60× below current guidance.
//
//  So the work moves here. The iPhone has no such budget, and this runs once, at
//  a moment the user is already waiting for a network call.
//
//  THE SECURITY DOESN'T MOVE WITH IT. The Worker stores
//  HMAC-SHA256(pepper, salt ‖ derivedKey), so an attacker holding the database
//  still has to run this same 600,000-iteration derivation for every password
//  they want to test. The cost per guess is unchanged — only the machine paying
//  it is. And because what's stored is a hash OF the derived key rather than the
//  key itself, a leaked table doesn't hand anyone a replayable credential.
//
//  This is the same shape 1Password and Bitwarden use.
//
//  THE SALT IS DERIVED FROM THE EMAIL, not random. It has to be reproducible on
//  every device before the server is contacted — a random per-account salt would
//  need fetching first, and "does this account exist?" is exactly the question an
//  enumeration attack asks. Deriving it from the address keeps logins offline-
//  computable while still making two people with the same password hash
//  differently. A per-app prefix stops the value being reusable anywhere else.
//

import Foundation
import CommonCrypto

// `nonisolated` because the whole point is to run OFF the main actor: this is
// hundreds of milliseconds of PBKDF2, called from `Task.detached`. The project
// builds with -default-isolation=MainActor, so without this the type is
// implicitly main-actor-isolated and every detached call warns today — and fails
// to compile under the Swift 6 language mode. It touches no shared state.
nonisolated enum PasswordCrypto {
    // OWASP's current floor for PBKDF2-HMAC-SHA256. The Worker refuses anything
    // below 100_000, so lowering this is a deliberate act, not a typo that ships.
    static let iterations = 600_000

    // Namespaces the salt to this app so the derived key can't be replayed
    // against another service that happens to use the same scheme.
    private static let saltPrefix = "tadah.pw.v1:"

    enum CryptoError: Error { case derivationFailed }

    // The 32-byte PBKDF2 output, lower-case hex — the exact shape
    // `validDerivedKey` accepts on the Worker.
    static func derive(password: String, email: String) throws -> String {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let salt = Data((saltPrefix + normalizedEmail).utf8)
        // PRECOMPOSED + UTF-8 so the same typed password derives the same key on
        // every device. "é" can be one code point or two, and an iPhone keyboard
        // and a paste from elsewhere disagree — without normalising, the same
        // password would fail to log in depending on how it was entered.
        let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)

        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes, passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count)
        }
        guard status == kCCSuccess else { throw CryptoError.derivationFailed }
        return out.map { String(format: "%02x", $0) }.joined()
    }

    // What the sign-in screen enforces before spending 600k iterations on it.
    //
    // Length only, deliberately. Composition rules ("one capital, one symbol")
    // push people toward Password1! and are no longer recommended by NIST; a
    // longer passphrase beats a short cryptic one, and this app's users include
    // people who find password rules genuinely hard.
    static let minimumPasswordLength = 8

    static func weaknessReason(for password: String) -> String? {
        if password.count < minimumPasswordLength {
            return String(localized: "Use at least 8 characters.")
        }
        return nil
    }
}
