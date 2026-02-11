import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct Grind_N_ChillApp: App {
    @State private var timerManager = TimerManager()
    private let sharedContainer = ModelContainerFactory.makeSharedContainer()
    
    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-disable-animations") {
            UIView.setAnimationsEnabled(false)
        }
#endif

        do {
            _ = try LegacyDataRepairService.repairCategoriesIfNeeded(in: sharedContainer.mainContext)
        } catch {
            print("Failed to run legacy data repair: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerManager)
        }
        .modelContainer(sharedContainer)
    }
}
