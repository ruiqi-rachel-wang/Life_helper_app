//  CreateView.swift
//
//  The Add tab — the picker shown when the user wants to add something.
//  Three entries: scan with the camera, upload from Photos, or create
//  by hand. Scan/Upload feed the OCR pipeline (→ Review); create-by-hand
//  opens a manual form.
//
//  "Sheet" layout from the spec: a big primary Scan hero + two smaller
//  secondary tiles. Currently Scan/Upload navigate to a mock Review;
//  the manual form arrives Week 2, the real camera + OCR in Week 4.
//

import SwiftUI

struct CreateView: View {
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("NEW ITEM")
                        .font(.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Color.faded)
                        .padding(.horizontal, 24)

                    heroTile
                        .padding(.horizontal, 14)
                        .padding(.top, 20)

                    secondaryRow
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                    Spacer()
                }
                .padding(.top, 48)
            }
            .navigationBarHidden(true)
        }
    }

    // Big primary action: Scan a document → Review.
    // TEMP (Week 4/6): jumps straight to a mock Review. Real version
    // opens the camera, runs OCR + extraction, then shows Review.
    private var heroTile: some View {
        NavigationLink {
            ReviewView()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOST COMMON")
                        .font(.eyebrow).tracking(1.4)
                        .foregroundStyle(Color.paper.opacity(0.55))
                    Text("Scan a document")
                        .font(.serifModal).tracking(-0.4)
                        .foregroundStyle(Color.paper)
                    Text("Camera · OCR runs on device")
                        .font(.subline)
                        .foregroundStyle(Color.paper.opacity(0.65))
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.paper.opacity(0.12))
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.paper)
                }
                .frame(width: 56, height: 56)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.ink))
        }
        .buttonStyle(.plain)
    }

    // Two smaller tiles: Upload from Photos, Create it yourself.
    private var secondaryRow: some View {
        HStack(spacing: 8) {
            NavigationLink {
                ReviewView()
            } label: {
                SecondaryTile(symbol: "photo.on.rectangle.angled",
                              title: "Upload from Photos")
            }
            .buttonStyle(.plain)

            NavigationLink {
                CreateFormPlaceholder()
            } label: {
                SecondaryTile(symbol: "square.and.pencil",
                              title: "Create it yourself")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Secondary tile

private struct SecondaryTile: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.bg)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 32, height: 32)

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
    }
}

// MARK: - Manual form placeholder (real form arrives Week 2)

private struct CreateFormPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.faint)
                        .onTapGesture { dismiss() }
                    Spacer()
                }
                Text("Create it yourself")
                    .font(.serifModal).tracking(-0.4).foregroundStyle(Color.ink)
                Text("Title, due date, optional steps. The manual form arrives in Week 2.")
                    .font(.subline).foregroundStyle(Color.faded)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    CreateView()
}
