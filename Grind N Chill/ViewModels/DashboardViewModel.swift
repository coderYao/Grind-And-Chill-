import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    struct DailyLedgerBreakdown {
        let grind: Decimal
        let chill: Decimal
        let entryCount: Int
    }

    struct DailyActivity: Identifiable {
        let id: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let unit: CategoryUnit
        let entryCount: Int
        let totalQuantity: Decimal
        let totalAmountUSD: Decimal
        let latestTimestamp: Date
    }

    struct StreakHighlight {
        let categoryID: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let type: CategoryType
        let streakDays: Int
        let progressText: String
    }

    private let ledgerService = LedgerService()
    private let streakService = StreakService()

    func balance(entries: [Entry]) -> Decimal {
        ledgerService.balance(for: entries)
    }

    func dailyLedgerChange(
        entries: [Entry],
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        entriesForDay(entries, day: day, calendar: calendar)
            .reduce(.zeroValue) { partialResult, entry in
                (partialResult + entry.amountUSD).rounded(scale: 2)
            }
    }

    func dailyLedgerBreakdown(
        entries: [Entry],
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> DailyLedgerBreakdown {
        let todayEntries = entriesForDay(entries, day: day, calendar: calendar)
        let split = todayEntries.reduce(into: (grind: Decimal.zeroValue, chill: Decimal.zeroValue)) { partialResult, entry in
            if entry.amountUSD >= .zeroValue {
                partialResult.grind = (partialResult.grind + entry.amountUSD).rounded(scale: 2)
            } else {
                partialResult.chill = (partialResult.chill + entry.amountUSD).rounded(scale: 2)
            }
        }

        return DailyLedgerBreakdown(
            grind: split.grind,
            chill: split.chill,
            entryCount: todayEntries.count
        )
    }

    func dailyActivities(
        entries: [Entry],
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyActivity] {
        struct Bucket {
            let id: UUID
            let title: String
            let symbolName: String
            let iconColor: CategoryIconColor
            let unit: CategoryUnit
            var entryCount: Int
            var totalQuantity: Decimal
            var totalAmountUSD: Decimal
            var latestTimestamp: Date
        }

        let todayEntries = entriesForDay(entries, day: day, calendar: calendar)
        var buckets: [UUID: Bucket] = [:]

        for entry in todayEntries {
            let category = entry.category
            let categoryID = category.id
            let quantity = activityQuantity(for: entry, category: category)

            if var existing = buckets[categoryID] {
                existing.entryCount += 1
                existing.totalQuantity += quantity
                existing.totalAmountUSD += entry.amountUSD
                if entry.timestamp > existing.latestTimestamp {
                    existing.latestTimestamp = entry.timestamp
                }
                buckets[categoryID] = existing
            } else {
                buckets[categoryID] = Bucket(
                    id: categoryID,
                    title: category.title,
                    symbolName: category.resolvedSymbolName,
                    iconColor: category.resolvedIconColor,
                    unit: category.resolvedUnit,
                    entryCount: 1,
                    totalQuantity: quantity,
                    totalAmountUSD: entry.amountUSD,
                    latestTimestamp: entry.timestamp
                )
            }
        }

        return buckets.values
            .map { bucket in
                DailyActivity(
                    id: bucket.id,
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    unit: bucket.unit,
                    entryCount: bucket.entryCount,
                    totalQuantity: bucket.totalQuantity.rounded(scale: 2),
                    totalAmountUSD: bucket.totalAmountUSD.rounded(scale: 2),
                    latestTimestamp: bucket.latestTimestamp
                )
            }
            .sorted { lhs, rhs in
                if lhs.latestTimestamp != rhs.latestTimestamp {
                    return lhs.latestTimestamp > rhs.latestTimestamp
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func streakHighlight(
        categories: [Category],
        entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StreakHighlight? {
        categories
            .compactMap { category -> StreakHighlight? in
                let streak = streakService.streak(for: category, entries: entries, now: now, calendar: calendar)
                guard streak > 0 else { return nil }

                return StreakHighlight(
                    categoryID: category.id,
                    title: category.title,
                    symbolName: category.resolvedSymbolName,
                    iconColor: category.resolvedIconColor,
                    type: category.resolvedType,
                    streakDays: streak,
                    progressText: progressText(for: category, entries: entries, now: now)
                )
            }
            .sorted { lhs, rhs in
                if lhs.streakDays != rhs.streakDays {
                    return lhs.streakDays > rhs.streakDays
                }
                if lhs.type != rhs.type {
                    return lhs.type == .goodHabit
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .first
    }

    func activityQuantityText(for activity: DailyActivity) -> String {
        switch activity.unit {
        case .time:
            return formatted(activity.totalQuantity, unit: .time)
        case .count:
            return "\(formatted(activity.totalQuantity, unit: .count)) count"
        case .money:
            return formatted(activity.totalQuantity, unit: .money)
        }
    }

    func absolute(_ value: Decimal) -> Decimal {
        value < .zeroValue ? value * Decimal(-1) : value
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

    private func entriesForDay(_ entries: [Entry], day: Date, calendar: Calendar) -> [Entry] {
        entries.filter { entry in
            calendar.isDate(entry.timestamp, inSameDayAs: day)
        }
    }

    private func activityQuantity(for entry: Entry, category: Category) -> Decimal {
        switch category.resolvedUnit {
        case .time:
            return Decimal(max(0, entry.durationMinutes))
        case .count:
            return entry.resolvedQuantity
        case .money:
            return entry.resolvedQuantity
        }
    }
}
