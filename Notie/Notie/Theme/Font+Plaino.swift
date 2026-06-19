//  Font+Plaino.swift
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
    static let serifTitle   = Font.system(size: 26, weight: .medium, design: .serif)
    static let serifModal   = Font.system(size: 24, weight: .medium, design: .serif)
    static let serifDetail  = Font.system(size: 22, weight: .medium, design: .serif)
    static let serifStat    = Font.system(size: 26, weight: .medium, design: .serif)
    static let serifSection = Font.system(size: 14, weight: .medium, design: .serif)

    // Sans (SF Pro)
    static let cardTitle = Font.system(size: 14.5, weight: .semibold)
    static let body14    = Font.system(size: 14)
    static let subline   = Font.system(size: 12)

    // Mono (SF Mono)
    static let eyebrow = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}
