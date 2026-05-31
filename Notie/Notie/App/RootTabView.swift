//  RootTabView.swift
//
//  The tab-bar shell shown when the app launches. Holds the 4 main
//  destinations (Inbox, Guides, Add, Settings); tapping a tab swaps
//  which screen is shown above the bar.
//
//  Tab selection is driven by a shared AppRouter so screens can jump
//  back to the Inbox after saving. The raised ＋ button from the design
//  spec is a Week 7 polish item; right now "Add" is a regular tab.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        return TabView(selection: $router.selectedTab) {
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(AppRouter.Tab.inbox)

            GuidesView()
                .tabItem { Label("Guides", systemImage: "books.vertical") }
                .tag(AppRouter.Tab.guides)

            CreateView()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(AppRouter.Tab.add)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .tint(Color.ink)
        .environment(router)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
