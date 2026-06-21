//  ItemStyle.swift
//
//  The view layer's mapping from domain data → presentation. This is the
//  ONLY place that turns a semantic ItemCategory into a color + SF Symbol,
//  and an ActionItem's amount/date into display strings. Keeping it here
//  (not on the model) is what lets the model stay UI-free.
//

import SwiftUI
import UIKit

extension UIImage {
    // Downscale so the longest side is ≤ maxDimension (keeps memory bounded).
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let newSize = CGSize(width: (size.width * ratio).rounded(),
                             height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // Stack pages top-to-bottom into one image (width = the widest page) so a
    // multi-page scan can be kept as a single stored photo. Each page is FIRST
    // downscaled — otherwise five full-res (~12 MP) photos build a multi-hundred-MB
    // bitmap that can crash on memory. Returns nil only if the list is empty or the
    // graphics context can't be created.
    static func stackedVertically(_ images: [UIImage], gap: CGFloat = 8,
                                  maxPageDimension: CGFloat = 1500) -> UIImage? {
        guard !images.isEmpty else { return nil }
        let pages = images.map { $0.downscaled(maxDimension: maxPageDimension) }
        let width = pages.map(\.size.width).max() ?? 0
        let height = pages.map(\.size.height).reduce(0, +) + gap * CGFloat(pages.count - 1)
        guard width > 0, height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { _ in
            var y: CGFloat = 0
            for image in pages {
                let x = (width - image.size.width) / 2   // center narrower pages
                image.draw(in: CGRect(origin: CGPoint(x: x, y: y), size: image.size))
                y += image.size.height + gap
            }
        }
    }
}

// Turn plain text into an AttributedString where URLs and phone numbers are
// tappable links (phones become tel:). Shared so screens render links the same.
//
// Chinese/Japanese text has no spaces, so the system link detector can swallow
// the words that follow a URL — "访问 nyc.gov/pay并登录" matched the whole
// "nyc.gov/pay并登录" as one (broken) link. We trim each detected URL back to its
// URL-safe ASCII prefix and rebuild a clean https URL so the link is valid and
// stops at the address.
nonisolated func linkified(_ string: String) -> AttributedString {
    var attr = AttributedString(string)
    let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
    guard let detector = try? NSDataDetector(types: types.rawValue) else { return attr }
    let ns = string as NSString
    for m in detector.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
        var range = m.range
        let url: URL?
        if m.resultType == .phoneNumber {
            url = m.phoneNumber.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
        } else {
            let matched = ns.substring(with: range)
            // Keep only the leading run of URL-safe ASCII; drop trailing CJK etc.
            let kept = matched.prefix { $0.isASCII && !$0.isWhitespace }
            if kept.count != matched.count {
                range = NSRange(location: range.location, length: (String(kept) as NSString).length)
            }
            let trimmed = String(kept)
            url = trimmed.contains("://") ? URL(string: trimmed) : URL(string: "https://" + trimmed)
        }
        guard let url,
              let sr = Range(range, in: string),
              let lo = AttributedString.Index(sr.lowerBound, within: attr),
              let hi = AttributedString.Index(sr.upperBound, within: attr) else { continue }
        attr[lo..<hi].link = url
        attr[lo..<hi].underlineStyle = .single
    }
    return attr
}

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
        case .auto:       return Color(hex: 0x4A7A8C)
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
        case .auto:       return "car.fill"
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
        return String(localized: "⚠ \(days) DAYS OVERDUE")
    }

    // The inbox subline: the meaningful facts only — amount (if any) + due date.
    // (No "checklist X of Y done" — the step progress lives on the Detail page.)
    var inboxSubtitle: String {
        let tail: String
        if isOverdue {
            tail = overdueText.map { _ in dueRelative } ?? String(localized: "overdue")
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
        if days == 0 { return String(localized: "today") }
        if days > 0  { return String(localized: "in \(days) days") }
        return String(localized: "\(-days) days overdue")
    }
}
