//  ItemStyle.swift
//
//  The view layer's mapping from domain data → presentation. This is the
//  ONLY place that turns a semantic ItemCategory into a color + SF Symbol,
//  and an ActionItem's amount/date into display strings. Keeping it here
//  (not on the model) is what lets the model stay UI-free.
//

import SwiftUI

// Shared due-date display used by both Review and Detail so they always match:
// "Jun 25, 2026" for a plain date, or "Jun 30, 8:30 AM" when it has a real time.
nonisolated func dueDisplay(_ date: Date, hasTime: Bool) -> String {
    hasTime
        ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        : date.formatted(.dateTime.month(.abbreviated).day().year())
}

extension ItemCategory {
    // Avatar circle color.
    var tint: Color {
        switch self {
        case .utility:    return Color(hex: 0x2A6FDB)
        case .government: return Color(hex: 0xC0532F)
        case .medical:    return Color(hex: 0x1F8A5B)
        case .finance:    return Color(hex: 0xa8651b)
        case .housing:    return Color(hex: 0x7a6a4a)
        case .work:       return Color(hex: 0x3B6E8F)
        case .personal:   return Color(hex: 0x7a6a4a)
        case .other:      return Color(hex: 0x7a6a4a)
        }
    }

    // SF Symbol shown in the avatar.
    var symbol: String {
        switch self {
        case .utility:    return "bolt.fill"
        case .government: return "building.columns.fill"
        case .medical:    return "cross.fill"
        case .finance:    return "creditcard.fill"
        case .housing:    return "house.fill"
        case .work:       return "briefcase.fill"
        case .personal:   return "bell.fill"
        case .other:      return "doc.text.fill"
        }
    }
}

extension ActionItem {
    // "$86.42" — nil when the item isn't a bill.
    var amountText: String? {
        guard let amount else { return nil }
        return amount.formatted(.currency(code: currency))
    }

    // "Jun 15" style short date.
    var dueText: String? {
        dueDate?.formatted(.dateTime.month(.abbreviated).day())
    }

    // The red banner line on Detail, e.g. "⚠ 2 DAYS OVERDUE". nil if fine.
    var overdueText: String? {
        guard isOverdue, let due = dueDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: due),
            to: Calendar.current.startOfDay(for: .now)).day ?? 0
        return "⚠ \(days) DAY\(days == 1 ? "" : "S") OVERDUE"
    }

    // The inbox subline: the meaningful facts only — amount (if any) + due date.
    // (No "checklist X of Y done" — the step progress lives on the Detail page.)
    var inboxSubtitle: String {
        let tail: String
        if isOverdue {
            tail = overdueText.map { _ in dueRelative } ?? "overdue"
        } else {
            tail = dueText ?? ""
        }
        return [amountText, tail].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    // "in 4 days" / "today" / "2 days overdue"
    var dueRelative: String {
        guard let due = dueDate else { return "" }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: due)).day ?? 0
        if days == 0 { return "today" }
        if days > 0  { return "in \(days) day\(days == 1 ? "" : "s")" }
        return "\(-days) day\(days == -1 ? "" : "s") overdue"
    }
}
