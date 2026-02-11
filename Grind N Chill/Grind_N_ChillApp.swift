import SwiftUI
import SwiftData

@main
struct Grind_N_ChillApp: App {
    @State private var timerManager = TimerManager()
    private let sharedContainer = ModelContainerFactory.makeSharedContainer()
    
    init() {
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
