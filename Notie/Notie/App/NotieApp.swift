//  NotieApp.swift
//
//  Entry point. Tells iOS: "when the app launches, show RootTabView."
//  This is the first code that runs. Exactly one @main exists per app.
//

import SwiftUI

@main
struct NotieApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
