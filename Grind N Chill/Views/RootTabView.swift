import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SessionView()
            }
            .tabItem {
                Label("Session", systemImage: "timer")
            }

            NavigationStack {
                CategoryListView()
            }
            .tabItem {
                Label("Categories", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}
