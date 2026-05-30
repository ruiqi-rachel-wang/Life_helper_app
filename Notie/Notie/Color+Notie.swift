//  Color+Notie.swift
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
    static let faded = Color(hex: 0x29261b, opacity: 0.58)
    static let faint = Color(hex: 0x29261b, opacity: 0.32)
    static let hair  = Color(hex: 0x29261b, opacity: 0.12)
    static let hairD = Color(hex: 0x29261b, opacity: 0.22)

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
