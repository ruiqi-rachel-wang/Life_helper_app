//  GuidesView.swift
//
//  The Guides tab — library of 5 life-event templates (Moving, Bank,
//  Job, License, Visa). Tapping one will (Week 7) create an Inbox
//  checklist from a static template.
//
//  Currently displays the cards + category filter chips with mock
//  data. Tapping does nothing yet; navigation is wired later in Week 1.
//

import SwiftUI

struct GuidesView: View {
    // Which category chip is selected. "All" shows everything.
    @State private var selectedCategory: String = "All"

    private let categories = ["All", "Housing", "Finance", "Work", "Government", "Other"]

    private var visibleGuides: [Guide] {
        selectedCategory == "All"
            ? Guide.all
            : Guide.all.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, 24)

                        categoryChips
                            .padding(.top, 18)

                        VStack(spacing: 10) {
                            ForEach(visibleGuides) { guide in
                                // Tapping a guide opens the Detail screen.
                                // Week 7: this instead creates a checklist
                                // from the guide's template.
                                NavigationLink {
                                    DetailView()
                                } label: {
                                    GuideCard(guide: guide)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 48)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIBRARY")
                .font(.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Color.faded)
            Text("Guides")
                .font(.serifTitle)
                .tracking(-0.6)
                .foregroundStyle(Color.ink)
            Text("Life events come with a stack of paperwork. Pick a guide and Notie walks you through it.")
                .font(.subline)
                .foregroundStyle(Color.faded)
                .lineSpacing(2)
                .padding(.top, 4)
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    // Horizontally scrolling filter chips.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = category == selectedCategory
                    Text(category)
                        .font(.eyebrow)
                        .tracking(0.4)
                        .foregroundStyle(isSelected ? Color.paper : Color.faded)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? Color.ink : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(Color.hairD, lineWidth: isSelected ? 0 : 1)
                        )
                        .onTapGesture { selectedCategory = category }
                }
            }
            .padding(.horizontal, 18)
        }
    }
}

// MARK: - Guide card

private struct GuideCard: View {
    let guide: Guide

    var body: some View {
        HStack(spacing: 14) {
            // 44×44 squircle with category color + white glyph
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(guide.color)
                Image(systemName: guide.symbol)
                    .foregroundStyle(.white)
                    .font(.system(size: 19, weight: .medium))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(guide.title)
                    .font(.cardTitle)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(guide.subtitle)
                    .font(.subline)
                    .foregroundStyle(Color.faded)
                    .lineLimit(1)
                Text("\(guide.category.uppercased()) · \(guide.stepCount) STEPS")
                    .font(.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(Color.faint)
                    .padding(.top, 4)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.hair, lineWidth: 1)
        )
    }
}

// MARK: - Guide model (mock data for now)

// The 5 starter life guides. In Week 7 each gets a real list of
// template steps; for now they're just card metadata.
struct Guide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let stepCount: Int
    let category: String
    let symbol: String   // SF Symbol name
    let color: Color

    static let all: [Guide] = [
        Guide(title: "Moving",
              subtitle: "Address change, utilities, mail forward",
              stepCount: 11, category: "Housing",
              symbol: "house.fill", color: Color(hex: 0x7a6a4a)),
        Guide(title: "Opening a bank account",
              subtitle: "ID requirements, what to bring",
              stepCount: 7, category: "Finance",
              symbol: "building.columns.fill", color: Color(hex: 0x2A6FDB)),
        Guide(title: "Starting a new job",
              subtitle: "Tax forms, direct deposit, benefits",
              stepCount: 9, category: "Work",
              symbol: "briefcase.fill", color: Color(hex: 0x1F8A5B)),
        Guide(title: "Driver's license",
              subtitle: "Renewal or first-time, by state",
              stepCount: 6, category: "Government",
              symbol: "creditcard.fill", color: Color(hex: 0xb14a2a)),
        Guide(title: "Green card / visa",
              subtitle: "Renewal forms, fees, photo, timeline",
              stepCount: 12, category: "Government",
              symbol: "globe", color: Color(hex: 0xa8651b)),
    ]
}

#Preview {
    GuidesView()
}
