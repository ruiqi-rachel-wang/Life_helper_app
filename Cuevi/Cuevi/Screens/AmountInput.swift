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

    // Tolerant parse: keep digits + one decimal point; empty clears the amount.
    private var text: Binding<String> {
        Binding(
            get: { amount.map { ($0 as NSDecimalNumber).stringValue } ?? "" },
            set: { newValue in
                let cleaned = newValue.filter { $0.isNumber || $0 == "." }
                amount = cleaned.isEmpty ? nil : Decimal(string: cleaned)
            })
    }
}
