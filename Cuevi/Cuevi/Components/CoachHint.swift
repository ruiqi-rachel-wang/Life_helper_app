//  CoachHint.swift
//
//  A small on-page hint used by the first-run TourGuide: an arrow + one line
//  of text sitting right next to the real button/row it's pointing at — a
//  translucent bubble, not a dimmed screen or a separate walkthrough. Tapping
//  the X ends the tour; doing the real action it's pointing at also dismisses
//  it (each call site wires that separately via TourGuide.advance/finish).
//

import SwiftUI

struct CoachHint: View {
    enum Arrow { case up, down }

    let text: LocalizedStringKey
    var arrow: Arrow = .down
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: arrow == .up ? "arrow.up" : "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accent)
                .padding(.top, 1)
            Text(text)
                .font(.subline).foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.35), lineWidth: 1))
    }
}

#Preview {
    VStack(spacing: 20) {
        CoachHint(text: "Tap **Add** below to scan your first document", arrow: .down) {}
        CoachHint(text: "Tap here to save it", arrow: .up) {}
    }
    .padding()
    .background(Color.bg)
}
