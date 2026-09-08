//  PlusUpgradeRow.swift
//
//  The "Tadah Plus … UPGRADE" row, in the one shape it has everywhere: sparkles,
//  the name, a line on what Plus adds, and the UPGRADE capsule. It sits in two
//  cards — the signed-in account card on Profile, and the membership card a
//  guest sees in the same place — and it has to be the same row in both, because
//  App Review tests the purchase by "open the Profile tab and tap UPGRADE" (our
//  subscription review notes), with and without an account.
//
//  Only the subtitle differs. A signed-in user is sold family lists and more
//  devices; a guest is told a purchase needs no account, and what an account
//  would add on top — the optional-registration wording guideline 5.1.1 asks
//  for, after build 5 was rejected (2026-09-07) for demanding sign-in first.
//

import SwiftUI

struct PlusUpgradeRow: View {
    let subtitle: LocalizedStringKey
    // The two cards space their rows differently: 14 above inside the account
    // card (it follows a divider, and is the last row), 12 above and below
    // between the membership card's dividers.
    var topPadding: CGFloat = 14
    var bottomPadding: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(Color.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tadah Plus").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("UPGRADE")
                    .font(.eyebrow).tracking(0.8).foregroundStyle(Color.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accent.opacity(0.12)))
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
