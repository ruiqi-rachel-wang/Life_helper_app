//  InboxView.swift
//
//  The home tab — the landing screen users open daily. Lists their
//  active tasks grouped by urgency (overdue, due soon, in progress,
//  upcoming).
//
//  Currently uses mock data inline to demonstrate the layout. Week 2
//  replaces mocks with real data from SwiftData storage.
//

import SwiftUI

struct InboxView: View {
    var body: some View {
        // NavigationStack lets rows push the Detail screen on top.
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)

                        InboxSection(title: "Needs attention", count: 1, tone: .bad) {
                            RowLink(item: .parkingTicket)
                        }

                        InboxSection(title: "Due this week", count: 2) {
                            RowLink(item: .conEdison)
                            InboxRowDivider()
                            RowLink(item: .insuranceCall)
                        }

                        InboxSection(title: "In progress", count: 1) {
                            RowLink(item: .moveOut)
                        }

                        InboxSection(title: "Upcoming", count: 1, isMuted: true) {
                            RowLink(item: .sutterVisit)
                        }

                        PrivacyBanner()
                            .padding(.horizontal, 14)
                            .padding(.top, 24)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 48)
                }
            }
            .navigationBarHidden(true)
        }
    }

    // Date eyebrow + title + active-count counter
    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLabel)
                    .font(.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Color.faded)
                Text("Inbox")
                    .font(.serifTitle)
                    .tracking(-0.6)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Text("5 active")
                .font(.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Color.faded)
        }
    }

    // "FRI · MAY 30"-style label built from today's date.
    private var dateLabel: String {
        let weekday  = Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let monthDay = Date.now.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        return "\(weekday) · \(monthDay)"
    }
}

// MARK: - Section (header + grouped white card)

private struct InboxSection<Content: View>: View {
    let title: String
    let count: Int
    var tone: Tone = .normal
    var isMuted: Bool = false
    @ViewBuilder var content: Content

    enum Tone { case normal, bad }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serifSection)
                    .foregroundStyle(
                        isMuted ? Color.faded
                        : tone == .bad ? Color.bad
                        : Color.ink
                    )
                Spacer()
                Text("\(count)")
                    .font(.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(Color.faded)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content
            }
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.hair, lineWidth: 1)
            )
            .padding(.horizontal, 14)
        }
        .padding(.top, 16)
    }
}

// One inbox row that pushes that item's own Detail screen when tapped.
// .plain keeps the row's styling instead of NavigationLink's blue tint.
private struct RowLink: View {
    let item: ActionItem
    var body: some View {
        NavigationLink {
            DetailView(item: item)
        } label: {
            InboxRow(
                glyph: item.glyph,
                color: item.color,
                title: item.title,
                subtitle: item.subtitle,
                isOverdue: item.isOverdue
            )
        }
        .buttonStyle(.plain)
    }
}

// Hairline between rows inside a section card — inset from the leading
// edge so it doesn't extend under the row's circular icon.
private struct InboxRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hair)
            .frame(height: 1)
            .padding(.leading, 64)
    }
}

// MARK: - Row

private struct InboxRow: View {
    let glyph: String       // SF Symbol name
    let color: Color        // circle background
    let title: String
    let subtitle: String
    var isOverdue: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color)
                Image(systemName: glyph)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subline)
                    .foregroundStyle(isOverdue ? Color.bad : Color.faded)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Privacy banner

// Quiet posture statement pinned to the bottom of the home list — the
// spec wants this visible without being loud.
private struct PrivacyBanner: View {
    var body: some View {
        Text("LOCAL OCR · NO BANK LINK · NO AUTOPAY")
            .font(.eyebrow)
            .tracking(0.4)
            .foregroundStyle(Color.faded)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bg)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 2)
            }
    }
}

#Preview {
    InboxView()
}
