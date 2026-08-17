//  AssigneeRow.swift
//
//  "Who is this for?" — the one control that files a to-do under a family member.
//
//  Two things it deliberately does:
//   • Defaults to whoever is using this phone, so the common case (adding your
//     own to-do) needs no thought at all.
//   • Offers **Everyone** as a real choice, not an empty state. A shared errand
//     — "book the family dentist" — belongs to nobody in particular, and those
//     show in every person's list.
//
//  Renders nothing at all when the account has no family, so a solo user never
//  sees a picker with one option in it.
//

import SwiftUI

struct AssigneeRow: View {
    @Environment(ProfileStore.self) private var profiles
    @Binding var profileID: UUID?

    var body: some View {
        if profiles.hasFamily {
            Menu {
                Picker("Who is this for?", selection: $profileID) {
                    ForEach(profiles.profiles) { profile in
                        Text(profile.displayName).tag(Optional(profile.id))
                    }
                    // Last, and separated: it's the "no one person" case.
                    Divider().overlay(Color.hair)
                    Text("Everyone").tag(UUID?.none)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15)).foregroundStyle(Color.faded)
                        .frame(width: 22)
                    // "For" alone left the Chinese as a dangling preposition —
                    // 给 is "to/give", so the row read as the fragment "给 妈妈".
                    // "Who it's for" / 给谁 is a whole phrase in both, and 给谁
                    // echoes the picker's own title (这是给谁的？).
                    Text("Who it's for").font(.body14).foregroundStyle(Color.ink)
                    Spacer()
                    Text(currentName)
                        .font(.body14).foregroundStyle(Color.faded)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11)).foregroundStyle(Color.faint)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
        }
    }

    private var currentName: String {
        profiles.profile(for: profileID)?.displayName ?? String(localized: "Everyone")
    }
}
