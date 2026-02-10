import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(AppStorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(AppStorageKeys.usdPerHour) private var usdPerHourRaw: Double = 18

    @Query(sort: \Category.title) private var categories: [Category]

    @State private var onboardingViewModel = OnboardingViewModel()

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
            }
    }
}

#Preview {
    ContentView()
        .environment(TimerManager())
        .modelContainer(for: [Category.self, Entry.self, BadgeAward.self], inMemory: true)
}
