import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let ledgerService = LedgerService()
    private let streakService = StreakService()

    func balance(entries: [Entry]) -> Decimal {
        ledgerService.balance(for: entries)
    }

    func streak(for category: Category, entries: [Entry], now: Date = .now) -> Int {
        streakService.streak(for: category, entries: entries, now: now)
    }

    func progressText(for category: Category, entries: [Entry], now: Date = .now) -> String {
        let minutes = streakService.totalMinutes(for: category, on: now, entries: entries)

        switch category.resolvedType {
        case .goodHabit:
            return "\(minutes)/\(category.dailyGoalMinutes)m today"
        case .quitHabit:
            return minutes == 0 ? "No relapses today" : "\(minutes)m logged today"
        }
    }
}
