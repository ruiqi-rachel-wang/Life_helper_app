//  AppRouter.swift
//
//  A tiny shared object that owns which tab is selected, so a deep screen
//  (e.g. the Create form or Review) can send the user back to the Inbox
//  after saving — "add something" should land you where the new item is.
//

import SwiftUI

@Observable
final class AppRouter {
    enum Tab: Hashable { case inbox, guides, add, profile }
    var selectedTab: Tab = .inbox

    // Set when a notification is tapped — the Inbox opens this item's Detail.
    var pendingItemID: UUID?

    func goToInbox() { selectedTab = .inbox }
}
