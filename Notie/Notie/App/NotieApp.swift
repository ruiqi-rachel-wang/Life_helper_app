//  NotieApp.swift
//
//  Entry point. Tells iOS: "when the app launches, show RootTabView."
//  This is the first code that runs. Exactly one @main exists per app.
//

import SwiftUI
import SwiftData

@main
struct NotieApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        // Sets up the on-device SwiftData store and injects a modelContext
        // into the environment so every screen can read/write items.
        .modelContainer(for: ActionItem.self)
    }
}
