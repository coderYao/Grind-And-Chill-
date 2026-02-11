import SwiftUI

struct RootTabView: View {
    @Environment(SyncMonitor.self) private var syncMonitor

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
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                syncStatusChip

                if let banner = syncMonitor.bannerMessage {
                    syncBanner(message: banner, isWarning: syncMonitor.isStatusWarning)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private var syncStatusChip: some View {
        HStack(spacing: 8) {
            if syncMonitor.status == .syncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: syncMonitor.statusSymbol)
            }

            Text(syncMonitor.statusTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(syncMonitor.isStatusWarning ? .orange : .secondary)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private func syncBanner(message: String, isWarning: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isWarning ? .orange : .green)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button {
                syncMonitor.clearBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
