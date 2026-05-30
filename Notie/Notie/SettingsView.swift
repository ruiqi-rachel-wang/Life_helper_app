//  SettingsView.swift
//
//  Language, reminder timing, privacy, notifications, export.
//
//  Stub for now. Real settings arrive Week 8.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("PREFERENCES")
                    .font(.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Color.faded)

                Text("Settings")
                    .font(.serifTitle)
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 4)

                Text("Language, reminders, privacy. Coming in Week 8.")
                    .font(.subline)
                    .foregroundStyle(Color.faint)
                    .padding(.top, 12)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
    }
}

#Preview {
    SettingsView()
}
