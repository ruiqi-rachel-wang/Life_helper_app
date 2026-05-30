//  RootTabView.swift
//
//  The tab-bar shell shown when the app launches. Holds the 4 main
//  destinations (Inbox, Guides, Add, Settings); tapping a tab swaps
//  which screen is shown above the bar.
//
//  The raised ＋ button from the design spec is a Week 7 polish item.
//  Right now "Add" is a regular tab.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray")
                }

            GuidesView()
                .tabItem {
                    Label("Guides", systemImage: "books.vertical")
                }

            CreateView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Color.ink)
    }
}

#Preview {
    RootTabView()
}
