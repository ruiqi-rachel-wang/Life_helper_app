//  Font+Cuevi.swift
//
//  Type scale tokens, mapping the spec's typography to Apple's system
//  fonts (New York serif, SF Pro sans, SF Mono). Used via
//  .font(.serifTitle), .font(.eyebrow), etc.
//
//  Letter-spacing (tracking) is applied at the call site via
//  .tracking(value) — SwiftUI's Font type doesn't carry it.
//

import SwiftUI

extension Font {
    // Serif (New York). Sizes trimmed from the spec to leave more room
    // for content on real device screens. Spec had 34/30/28/32 — trimmed.
    // Bumped ~2pt across the scale 2026-07-06 (tester feedback: bigger text —
    // many users read English slowly, small type makes that worse).
    static let serifTitle   = Font.system(size: 28, weight: .medium, design: .serif)
    static let serifModal   = Font.system(size: 26, weight: .medium, design: .serif)
    static let serifDetail  = Font.system(size: 24, weight: .medium, design: .serif)
    static let serifStat    = Font.system(size: 28, weight: .medium, design: .serif)
    static let serifSection = Font.system(size: 16, weight: .medium, design: .serif)

    // Sans (SF Pro). `body14` keeps its historical name (used everywhere)
    // even though the size has grown.
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let body14    = Font.system(size: 15.5)
    static let subline   = Font.system(size: 13.5)

    // Mono (SF Mono)
    static let eyebrow = Font.system(size: 11.5, weight: .medium, design: .monospaced)
}
