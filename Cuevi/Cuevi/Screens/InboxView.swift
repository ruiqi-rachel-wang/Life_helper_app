//  InboxView.swift
//
//  The home tab — the daily landing screen. Reads items live from the
//  SwiftData store (@Query) and groups them by urgency at render time.
//  Done items collect in a section at the bottom until deleted.
//
//  Marking done / deleting / editing on the Detail screen flows back here
//  automatically, because both screens share the same stored objects.
//

import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \ActionItem.createdAt, order: .reverse) private var items: [ActionItem]

    // TEMP (Week 2): seed sample items once on first launch so a fresh
    // install isn't empty while testing. Real app starts empty.
    @AppStorage("didSeedSamples") private var didSeed = false

    // Urgency buckets — computed by the pure, tested grouping function.
    private var buckets: InboxBuckets { items.groupedForInbox() }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)

                        if items.isEmpty {
                            emptyState
                        } else {
                            let b = buckets
                            section("Needs attention", b.needsAttention, tone: .bad)
                            section("Due this week", b.dueThisWeek)
                            section("In progress", b.inProgress)
                            section("Upcoming", b.upcoming, muted: true)
                            section("Done", b.done, muted: true, done: true)
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
            // Notification tap → open that item's Detail. The binding finds
            // the item by the id the delegate stashed in the router.
            .navigationDestination(item: pendingItem) { item in
                DetailView(item: item)
            }
        }
        .task {
            if !didSeed {
                for sample in ActionItem.samples { context.insert(sample) }
                didSeed = true
            }
        }
    }

    // Resolves router.pendingItemID to the actual item; clearing it pops.
    private var pendingItem: Binding<ActionItem?> {
        Binding(
            get: { items.first { $0.id == router.pendingItemID } },
            set: { if $0 == nil { router.pendingItemID = nil } }
        )
    }

    // MARK: masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLabel)
                    .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                Text("To-Dos & Reminders")
                    .font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
            }
            Spacer()
            Text("\(buckets.activeCount) active")
                .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faded)
        }
    }

    private var dateLabel: String {
        let weekday  = Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let monthDay = Date.now.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        return "\(weekday) · \(monthDay)"
    }

    // MARK: a section (only renders when it has items)

    @ViewBuilder
    private func section(_ title: String, _ rows: [ActionItem],
                         tone: SectionTone = .normal,
                         muted: Bool = false,
                         done: Bool = false) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    // Section titles are app strings passed in as a String, so wrap
                    // in LocalizedStringKey to localize them (a plain Text(String)
                    // would show them verbatim).
                    Text(LocalizedStringKey(title))
                        .font(.serifSection)
                        .foregroundStyle(
                            muted ? Color.faded
                            : tone == .bad ? Color.bad
                            : Color.ink
                        )
                    Spacer()
                    Text("\(rows.count)")
                        .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faded)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index != 0 { InboxRowDivider() }
                        RowLink(item: item, done: done)
                    }
                }
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                .padding(.horizontal, 14)
            }
            .padding(.top, 16)
        }
    }

    // The empty Inbox is a teacher, not a dead end: the three ways to start,
    // with colorful icons (tester feedback: make what-to-do-next obvious).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing here yet — three ways to start")
                .font(.serifSection).foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            emptyRow("camera.viewfinder", Color.sourceScanned,
                     "Scan a letter or bill",
                     "Tap ＋ below, then Scan — Cuevi explains it and builds your steps.")
            emptyRow("books.vertical.fill", Color.sourceGuide,
                     "Pick a life guide",
                     "Moving, taxes, driver's license… ready-made checklists for life in the U.S.")
            emptyRow("square.and.pencil", Color.accent,
                     "Add it yourself",
                     "A quick to-do with a date — Cuevi reminds you before it's due.")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func emptyRow(_ symbol: String, _ color: Color,
                          _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 20)).foregroundStyle(color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cardTitle).foregroundStyle(Color.ink)
                Text(body).font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

enum SectionTone { case normal, bad }

// MARK: - Row link

private struct RowLink: View {
    let item: ActionItem
    var done: Bool = false

    var body: some View {
        NavigationLink {
            DetailView(item: item)
        } label: {
            InboxRow(
                glyph: item.category.symbol,
                color: item.category.tint,
                title: item.title,
                subtitle: done ? String(localized: "Completed") : item.inboxSubtitle,
                isOverdue: item.isOverdue,
                done: done
            )
        }
        .buttonStyle(.plain)
    }
}

private struct InboxRowDivider: View {
    var body: some View {
        Rectangle().fill(Color.hair).frame(height: 1).padding(.leading, 64)
    }
}

private struct InboxRow: View {
    let glyph: String
    let color: Color
    let title: String
    let subtitle: String
    var isOverdue: Bool = false
    var done: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.faint : color)
                Image(systemName: done ? "checkmark" : glyph)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(done ? Color.faded : Color.ink)
                    .strikethrough(done, color: Color.faded)
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

private struct PrivacyBanner: View {
    var body: some View {
        Text("On-device scanning · No bank login · No autopay")
            .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faded)
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bg)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accent).frame(width: 2)
            }
    }
}

#Preview {
    InboxView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
