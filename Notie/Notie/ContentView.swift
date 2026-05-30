import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("TUE · JUN 11")
                    .font(.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Color.faded)

                Text("Inbox")
                    .font(.serifTitle)
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 4)

                cardPreview
                    .padding(.top, 24)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
    }

    var cardPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Con Edison · electricity")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)

            Text("$86.42 · Sun Jun 15")
                .font(.subline)
                .foregroundStyle(Color.faded)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.sourceScanned)
                    .frame(width: 6, height: 6)
                Text("SCANNED")
                    .font(.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(Color.faded)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.hair, lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
