import SwiftUI

extension Font {
    // Serif (New York)
    static let serifTitle   = Font.system(size: 34, weight: .medium, design: .serif)
    static let serifModal   = Font.system(size: 30, weight: .medium, design: .serif)
    static let serifDetail  = Font.system(size: 28, weight: .medium, design: .serif)
    static let serifStat    = Font.system(size: 32, weight: .medium, design: .serif)
    static let serifSection = Font.system(size: 14, weight: .medium, design: .serif)

    // Sans (SF Pro)
    static let cardTitle = Font.system(size: 14.5, weight: .semibold)
    static let body14    = Font.system(size: 14)
    static let subline   = Font.system(size: 12)

    // Mono (SF Mono)
    static let eyebrow = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}
