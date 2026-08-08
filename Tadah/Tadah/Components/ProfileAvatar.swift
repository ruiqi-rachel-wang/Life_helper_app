//  ProfileAvatar.swift
//
//  The monogram circle used everywhere a family member appears: the switcher
//  strip under the identity row, the Family Sharing grid, and the account card.
//  One component so a person looks the same in all three places.
//
//  Colours come from Profile.colorIndex (assigned round-robin as profiles are
//  added), so each family member is recognisable at a glance without a photo.
//  Kept in the theme layer, not the model — Profile stays UI-free.
//

import SwiftUI

extension Color {
    // Muted, paper-friendly hues that sit next to Color.accent without clashing.
    // Index 0 is the accent itself, so the owner matches the rest of the app.
    static let profilePalette: [Color] = [
        Color(hex: 0xb14a2a),   // accent — burnt sienna (owner)
        Color(hex: 0x2A6FDB),   // blue
        Color(hex: 0x1F8A5B),   // green
        Color(hex: 0xa8651b),   // amber
        Color(hex: 0x7A5AA8),   // violet
        Color(hex: 0x4A7A8C),   // slate
    ]

    static func profileTint(_ index: Int) -> Color {
        profilePalette[((index % profilePalette.count) + profilePalette.count) % profilePalette.count]
    }
}

struct ProfileAvatar: View {
    let initials: String
    let colorIndex: Int
    var size: CGFloat = 44
    var isSelected: Bool = false

    private var tint: Color { .profileTint(colorIndex) }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.15))
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        // The current profile gets a ring, so "who am I looking at" is obvious
        // even when several circles are on screen.
        .overlay {
            Circle().stroke(isSelected ? tint : .clear, lineWidth: 2)
                .padding(-3)
        }
    }
}

// The dashed "add someone" circle that ends the strip and the grid.
struct AddProfileCircle: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.hairD, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Image(systemName: "plus")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(Color.faded)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 14) {
        ProfileAvatar(initials: "J", colorIndex: 0, isSelected: true)
        ProfileAvatar(initials: "M", colorIndex: 1)
        ProfileAvatar(initials: "D", colorIndex: 2)
        AddProfileCircle()
    }
    .padding()
    .background(Color.paper)
}
