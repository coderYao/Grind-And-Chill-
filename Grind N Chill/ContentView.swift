import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncMonitor.self) private var syncMonitor

    @AppStorage(AppStorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(AppStorageKeys.usdPerHour) private var usdPerHourRaw: Double = 18

    @Query(sort: \Category.title) private var categories: [Category]

    @State private var onboardingViewModel = OnboardingViewModel()
    @State private var hasRunInitialSyncMaintenance = false

    private var shouldPresentOnboarding: Bool {
        hasCompletedOnboarding == false && categories.isEmpty
    }

    var body: some View {
        RootTabView()
            .fullScreenCover(
                isPresented: Binding(
                    get: { shouldPresentOnboarding },
                    set: { _ in }
                )
            ) {
                OnboardingView(viewModel: onboardingViewModel) { rate in
                    usdPerHourRaw = rate
                    hasCompletedOnboarding = true
                }
            }
            .onAppear {
                if hasCompletedOnboarding == false && categories.isEmpty == false {
                    hasCompletedOnboarding = true
                }
                runSyncMaintenance(force: false)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                syncMonitor.markRefreshRequested()
                runSyncMaintenance(force: true)
            }
    }

    private func runSyncMaintenance(force: Bool) {
        if force == false, hasRunInitialSyncMaintenance {
            return
        }

        hasRunInitialSyncMaintenance = true

        do {
            let report = try SyncConflictResolverService.resolveConflictsIfNeeded(in: modelContext)
            syncMonitor.postMergeReport(report)
            if report.totalResolved == 0 {
                syncMonitor.markUpToDateIfNeeded()
            }
        } catch {
            syncMonitor.postError("Could not finalize sync merge: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
        .environment(TimerManager())
        .environment(SyncMonitor(cloudKitEnabled: false))
        .modelContainer(for: [Category.self, Entry.self, BadgeAward.self, SyncEventHistory.self], inMemory: true)
}
