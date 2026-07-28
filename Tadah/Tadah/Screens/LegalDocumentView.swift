//  LegalDocumentView.swift
//
//  Shows a legal document (privacy policy / terms) IN-APP in a sheet, so the user
//  never leaves Tadah to read it. Lightweight Markdown renderer: it styles
//  headings / bullets / tables / dividers by line prefix and uses AttributedString
//  for inline **bold** and [links]. Content comes from LegalContent.
//

import SwiftUI

struct LegalDocumentView: View {
    let title: LocalizedStringKey
    let markdown: String
    @Environment(\.dismiss) private var dismiss

    private var lines: [String] { markdown.components(separatedBy: "\n") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Color.clear.frame(height: 4)
        } else if line == "---" {
            Divider().overlay(Color.hair)
        } else if line.hasPrefix("# ") {
            Text(inline(line.dropFirst(2))).font(.serifTitle).foregroundStyle(Color.ink)
        } else if line.hasPrefix("## ") {
            Text(inline(line.dropFirst(3))).font(.serifModal).foregroundStyle(Color.ink).padding(.top, 8)
        } else if line.hasPrefix("### ") {
            Text(inline(line.dropFirst(4))).font(.cardTitle).foregroundStyle(Color.ink).padding(.top, 4)
        } else if line.hasPrefix("|") {
            tableRow(line)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.body14).foregroundStyle(Color.faded)
                Text(inline(line.dropFirst(2))).font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
            }
        } else {
            Text(inline(Substring(line))).font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
        }
    }

    // A markdown table row "| a | b |" → cells joined; skip the |---| separator.
    @ViewBuilder
    private func tableRow(_ line: String) -> some View {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let isSeparator = cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } }
        if !isSeparator {
            Text(inline(Substring(cells.joined(separator: "  ·  "))))
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
        }
    }

    // Inline markdown (**bold**, [links], `code`) → AttributedString; plain on failure.
    private func inline(_ s: Substring) -> AttributedString {
        let str = String(s)
        return (try? AttributedString(
            markdown: str,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(str)
    }
}
