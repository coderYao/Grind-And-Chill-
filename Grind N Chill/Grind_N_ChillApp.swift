import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct Grind_N_ChillApp: App {
    @State private var timerManager = TimerManager()
    @State private var syncMonitor: SyncMonitor
    private let sharedContainer: ModelContainer

    init() {
        let cloudKitEnabled = ModelContainerFactory.isCloudKitEnabledForCurrentLaunch()
        sharedContainer = ModelContainerFactory.makeSharedContainer()
        _syncMonitor = State(
            initialValue: SyncMonitor(
                cloudKitEnabled: cloudKitEnabled,
                modelContext: sharedContainer.mainContext
            )
        )

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
#endif

        do {
            _ = try LegacyDataRepairService.repairCategoriesIfNeeded(in: sharedContainer.mainContext)
            try GrindNChillMigrationPlan.repairStoreDataIfNeeded(in: sharedContainer.mainContext)
        } catch {
            print("Failed to run legacy data repair: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerManager)
                .environment(syncMonitor)
        }
        .modelContainer(sharedContainer)
    }
}
