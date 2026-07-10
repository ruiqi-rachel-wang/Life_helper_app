//  WelcomeTourView.swift
//
//  The one-time first-run walkthrough — 3 short, skippable pages that replace
//  the old "3 seeded example items" as how a new user learns the app:
//    1. what Cuevi is (confusing mail → simple steps + reminders)
//    2. the THREE ways to add something (scan / life guide / yourself)
//    3. what happens after (checklist, reminders, check off)
//
//  Shown by RootTabView on first launch (before the notification primer) and
//  replayable from the empty Inbox. Keep it short — users skip onboarding, so
//  the teaching empty state is the fallback that says the same three ways.
//

import SwiftUI

struct WelcomeTourView: View {
    /// Called when the user finishes or skips — the caller persists "seen".
    var onDone: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    whatIsCuevi.tag(0)
                    threeWays.tag(1)
                    staysOnTrack.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < 2 { withAnimation { page += 1 } } else { onDone() }
                } label: {
                    Text(page < 2 ? "Continue" : "Get started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24).padding(.bottom, 24)
            }

            Button { onDone() } label: {
                Text("Skip")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.faded)
                    .padding(.horizontal, 18).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: page 1 — what Cuevi is

    private var whatIsCuevi: some View {
        pageLayout {
            ZStack {
                Circle().fill(Color.accent.opacity(0.14)).frame(width: 110, height: 110)
                Image(systemName: "envelope.open.fill").font(.system(size: 46)).foregroundStyle(Color.accent)
            }
            Text("Welcome to Cuevi").font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
            Text("Confusing letters, bills, and official mail — turned into simple steps and reminders, in your language.")
                .font(.body14).foregroundStyle(Color.faded)
                .multilineTextAlignment(.center).lineSpacing(4)
        }
    }

    // MARK: page 2 — the three ways to add

    private var threeWays: some View {
        pageLayout {
            Text("Three ways to add something")
                .font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink).multilineTextAlignment(.center)
            VStack(spacing: 14) {
                tourRow("camera.viewfinder", Color.sourceScanned, "Scan a document",
                        "Snap a photo of a bill, letter, or notice — Cuevi explains it and builds your to-do.")
                tourRow("books.vertical.fill", Color.sourceGuide, "Pick a life guide",
                        "Moving, taxes, driver's license… ready-made checklists for life in the U.S.")
                tourRow("square.and.pencil", Color.accent, "Add it yourself",
                        "A quick to-do with a date — Cuevi reminds you before it's due.")
            }
        }
    }

    // MARK: page 3 — what happens after

    private var staysOnTrack: some View {
        pageLayout {
            Text("Cuevi keeps you on track")
                .font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink).multilineTextAlignment(.center)
            VStack(spacing: 14) {
                tourRow("checklist", Color.sourceGuide, "Simple checklists",
                        "Each item becomes a simple checklist.")
                tourRow("bell.badge.fill", Color.accent, "Reminders",
                        "You get reminders before things are due.")
                tourRow("checkmark.circle.fill", Color.ok, "Check things off",
                        "Check off steps as you finish them — or swipe a row to mark it done.")
            }
        }
    }

    // MARK: pieces

    private func pageLayout(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 22) {
            Spacer()
            content()
            Spacer()
            Spacer().frame(height: 20)   // room above the page dots
        }
        .padding(.horizontal, 30)
    }

    private func tourRow(_ symbol: String, _ color: Color,
                         _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14))
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(color)
            }
            .frame(width: 48, height: 48)

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

#Preview {
    WelcomeTourView(onDone: {})
}
