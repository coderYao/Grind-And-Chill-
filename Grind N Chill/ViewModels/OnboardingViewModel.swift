import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class OnboardingViewModel {
    private let settingsViewModel = SettingsViewModel()

    var desiredUSDPerHour: Double = 18
    var includeStarterCategories = true
    var latestError: String?

    func normalizeRate() {
        desiredUSDPerHour = settingsViewModel.normalizedUSDPerHour(desiredUSDPerHour)
    }

    func complete(modelContext: ModelContext) -> Bool {
        normalizeRate()

        guard desiredUSDPerHour > 0 else {
            latestError = "Choose a USD per hour greater than zero."
            return false
        }

        if includeStarterCategories {
            do {
                try CategorySeeder.seedIfNeeded(in: modelContext)
            } catch {
                latestError = "Could not create starter categories: \(error.localizedDescription)"
                return false
            }
        }

        latestError = nil
        return true
    }
}
