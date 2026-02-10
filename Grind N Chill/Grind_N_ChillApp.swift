import SwiftUI
import SwiftData

@main
struct Grind_N_ChillApp: App {
    @State private var timerManager = TimerManager()
    private let sharedContainer = ModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(timerManager)
        }
        .modelContainer(sharedContainer)
    }
}
