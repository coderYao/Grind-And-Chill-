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
        let progress = streakService.totalProgress(for: category, on: now, entries: entries)
        let goal = Decimal(max(0, category.dailyGoalMinutes))
        let thresholdText = formatted(goal, unit: category.resolvedUnit)

        switch category.resolvedType {
        case .goodHabit:
            return "\(formatted(progress, unit: category.resolvedUnit))/\(thresholdText) today"
        case .quitHabit:
            return progress == .zeroValue
                ? "No relapses today • Target < \(thresholdText)"
                : "\(formatted(progress, unit: category.resolvedUnit)) logged today • Target < \(thresholdText)"
        }
    }

    private func formatted(_ value: Decimal, unit: CategoryUnit) -> String {
        switch unit {
        case .time:
            let minutes = NSDecimalNumber(decimal: value).intValue
            return "\(max(0, minutes))m"
        case .count:
            let number = NSDecimalNumber(decimal: value).doubleValue
            return number.formatted(.number.precision(.fractionLength(0 ... 2)))
        case .money:
            return value.formatted(.currency(code: "USD"))
        }
    }
}
