//  AmountInput.swift
//
//  Shared editable money field ("$ 0.00") bound to a Decimal?, used by both the
//  Review and Detail edit screens so the amount is editable the same way in each.
//

import SwiftUI

struct AmountInput: View {
    @Binding var amount: Decimal?

    var body: some View {
        HStack(spacing: 2) {
            Text("$").font(.subline).foregroundStyle(Color.faded)
            TextField("0.00", text: text)
                .keyboardType(.decimalPad)
                .font(.serifStat).foregroundStyle(Color.ink)
        }
    }

    // Tolerant parse (shared AmountParsing); empty clears the amount.
    private var text: Binding<String> {
        Binding(
            get: { amount.map { ($0 as NSDecimalNumber).stringValue } ?? "" },
            set: { amount = AmountParsing.decimal(from: $0) })
    }
}

// Tolerant money-string parsing, shared by AmountInput and the manual create
// form. iOS shows a COMMA on many locales' decimal keyboards, so "12,50" must
// read as 12.50 — while "1,234" (three digits after) stays a thousands comma.
// Pure → unit-tested.
nonisolated enum AmountParsing {
    static func decimal(from raw: String) -> Decimal? {
        var s = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        if !s.contains("."),
           s.filter({ $0 == "," }).count == 1,
           let comma = s.firstIndex(of: ","),
           s.distance(from: s.index(after: comma), to: s.endIndex) <= 2 {
            s = s.replacingOccurrences(of: ",", with: ".")   // decimal comma
        } else {
            s = s.replacingOccurrences(of: ",", with: "")    // thousands comma(s)
        }
        return s.isEmpty ? nil : Decimal(string: s)
    }
}
