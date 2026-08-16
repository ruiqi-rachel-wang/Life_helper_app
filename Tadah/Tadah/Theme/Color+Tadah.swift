//  Color+Tadah.swift
//
//  Extends SwiftUI's Color with all design tokens from the spec.
//  Single source of truth — `Color.paper`, `Color.ink`, `Color.accent`
//  are used across every screen. Change one here, every screen updates.
//
//  "extension Color { ... }" lets us add properties/methods to Apple's
//  built-in Color type without subclassing it.
//

import SwiftUI

extension Color {
    // Surface
    static let bg    = Color(hex: 0xf4f1ea)
    static let paper = Color(hex: 0xfbf9f4)
    static let card  = Color(hex: 0xffffff)

    // Ink
    static let ink   = Color(hex: 0x29261b)
    // SECONDARY TEXT. 0.58 → 0.68 on 2026-08-16: at 0.58 this failed WCAG AA on
    // `paper` and date chips, "Specific time" and every field placeholder were
    // reported as literally unreadable. Now 5.2:1 on `paper` and 5.0:1 on `bg` —
    // clears the 4.5:1 floor for small text while staying visibly lighter than
    // `ink` (14.4:1), so it still reads as secondary.
    //
    // THIS IS THE LIGHTEST INK ANY TEXT MAY USE. Anything below it fails AA at
    // 13–15pt, which is nearly every string in this app.
    static let faded = Color(hex: 0x29261b, opacity: 0.68)
    // NOT FOR TEXT — icons, hairline strokes, and inactive fills only.
    //
    // 0.32 → 0.46 → 0.58 on 2026-08-16. The first bump was aimed at the wrong
    // floor: 0.46 measures 2.7:1 on `paper`, which is under the 4.5:1 AA minimum
    // for small text AND under the 3:1 minimum for interactive non-text (chevrons,
    // the ⊖ delete buttons, disabled button fills). It fixed nothing it was meant
    // to fix, and the "it is now legible" note above it was simply wrong.
    //
    // The real fix was two-part. This token now sits at 0.58 — 3.8:1 on `paper`,
    // 3.7:1 on `bg`, so every control drawn in it clears WCAG 1.4.11's 3:1 — and
    // every use of it that carried WORDS (password requirements, the legal and
    // AI-accuracy disclaimers, "OPTIONAL", guide category labels, the version
    // string) moved to `faded`, which is a text-legal colour. Disabled primary
    // buttons keep a white label on a 0.58 fill: 4.0:1, up from 2.9:1, and
    // inactive controls are explicitly exempt from the 4.5:1 text rule.
    //
    // Before reaching for this on a `Text`, don't — use `faded`.
    static let faint = Color(hex: 0x29261b, opacity: 0.58)
    static let hair  = Color(hex: 0x29261b, opacity: 0.12)
    static let hairD = Color(hex: 0x29261b, opacity: 0.22)

    // The placeholder / "what goes in this field" ink. NOT `faded`, and never
    // SwiftUI's default placeholder gray: on this cream paper the system gray
    // measures ~2.3:1 and `faded` ~3.8:1, both under the 4.5:1 WCAG AA floor for
    // 13–15pt text — testers reported twice that they couldn't read what a field
    // was asking for. 0.68 measures 4.7:1 on `paper` and 5.0:1 on `bg` while
    // staying visibly lighter than typed text (ink at 1.0 is ~13:1), so an empty
    // field still reads as empty. Use it via `fieldPrompt(_:)`, never inline.
    static let hint  = Color(hex: 0x29261b, opacity: 0.68)

    // Accents
    static let accent = Color(hex: 0xb14a2a)   // burnt sienna
    static let ok     = Color(hex: 0x1f6b4a)   // success / done
    static let warn   = Color(hex: 0xa8651b)   // due-soon (amber)
    static let bad    = Color(hex: 0xa93420)   // overdue / penalty

    // Source tags
    static let sourceScanned = Color(hex: 0x2A6FDB)
    static let sourceGuide   = Color(hex: 0x1F8A5B)
    static let sourceCustom  = Color(hex: 0x7a6a4a)

    init(hex: Int, opacity: Double = 1.0) {
        self.init(
            red:   Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8)  & 0xff) / 255.0,
            blue:  Double( hex        & 0xff) / 255.0,
            opacity: opacity
        )
    }
}
