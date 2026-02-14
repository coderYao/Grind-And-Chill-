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

    struct CategoryMoneyBreakdown: Identifiable {
        let id: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let totalAmountUSD: Decimal
        let entryCount: Int
    }

    struct StreakHighlight {
        let categoryID: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let type: CategoryType
        let streakDays: Int
        let cadence: StreakCadence
        let progressText: String
    }

    struct WeeklyTrend {
        let currentNet: Decimal
        let previousNet: Decimal
        let delta: Decimal
    }

    struct WeeklyCategoryInsight {
        let categoryID: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let totalAmountUSD: Decimal
    }

    struct StreakRiskAlert: Identifiable {
        let id: UUID
        let categoryID: UUID
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor
        let type: CategoryType
        let message: String
        let severity: Int
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
            guard let category = entry.category else { continue }
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

    func dailyCategoryMoneyBreakdown(
        entries: [Entry],
        on day: Date = .now,
        calendar: Calendar = .current
    ) -> (grind: [CategoryMoneyBreakdown], chill: [CategoryMoneyBreakdown]) {
        struct Bucket {
            let id: UUID
            let title: String
            let symbolName: String
            let iconColor: CategoryIconColor
            var grindTotal: Decimal
            var chillTotal: Decimal
            var grindEntryCount: Int
            var chillEntryCount: Int
        }

        let todayEntries = entriesForDay(entries, day: day, calendar: calendar)
        var buckets: [UUID: Bucket] = [:]

        for entry in todayEntries {
            guard let category = entry.category else { continue }
            let id = category.id

            if buckets[id] == nil {
                buckets[id] = Bucket(
                    id: id,
                    title: category.title,
                    symbolName: category.resolvedSymbolName,
                    iconColor: category.resolvedIconColor,
                    grindTotal: .zeroValue,
                    chillTotal: .zeroValue,
                    grindEntryCount: 0,
                    chillEntryCount: 0
                )
            }

            guard var bucket = buckets[id] else { continue }
            if entry.amountUSD >= .zeroValue {
                bucket.grindTotal = (bucket.grindTotal + entry.amountUSD).rounded(scale: 2)
                bucket.grindEntryCount += 1
            } else {
                bucket.chillTotal = (bucket.chillTotal + absolute(entry.amountUSD)).rounded(scale: 2)
                bucket.chillEntryCount += 1
            }
            buckets[id] = bucket
        }

        let grind = buckets.values
            .filter { $0.grindTotal > .zeroValue }
            .map { bucket in
                CategoryMoneyBreakdown(
                    id: bucket.id,
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.grindTotal,
                    entryCount: bucket.grindEntryCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalAmountUSD != rhs.totalAmountUSD {
                    return lhs.totalAmountUSD > rhs.totalAmountUSD
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let chill = buckets.values
            .filter { $0.chillTotal > .zeroValue }
            .map { bucket in
                CategoryMoneyBreakdown(
                    id: bucket.id,
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.chillTotal,
                    entryCount: bucket.chillEntryCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalAmountUSD != rhs.totalAmountUSD {
                    return lhs.totalAmountUSD > rhs.totalAmountUSD
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        return (grind, chill)
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
                    cadence: category.resolvedStreakCadence,
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

    func weeklyTrend(
        entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyTrend {
        let today = calendar.startOfDay(for: now)
        guard let currentStartAnchor = calendar.date(byAdding: .day, value: -6, to: today),
              let previousStartAnchor = calendar.date(byAdding: .day, value: -7, to: currentStartAnchor)
        else {
            return WeeklyTrend(currentNet: .zeroValue, previousNet: .zeroValue, delta: .zeroValue)
        }

        let currentStart = calendar.startOfDay(for: currentStartAnchor)
        let previousStart = calendar.startOfDay(for: previousStartAnchor)
        let currentRange = DateInterval(start: currentStart, end: now.addingTimeInterval(1))
        let previousRange = DateInterval(start: previousStart, end: currentStart)

        let currentNet = entriesInRange(entries, range: currentRange).reduce(.zeroValue) { partialResult, entry in
            (partialResult + entry.amountUSD).rounded(scale: 2)
        }
        let previousNet = entriesInRange(entries, range: previousRange).reduce(.zeroValue) { partialResult, entry in
            (partialResult + entry.amountUSD).rounded(scale: 2)
        }

        return WeeklyTrend(
            currentNet: currentNet,
            previousNet: previousNet,
            delta: (currentNet - previousNet).rounded(scale: 2)
        )
    }

    func topWeeklyCategories(
        entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (grind: WeeklyCategoryInsight?, chill: WeeklyCategoryInsight?) {
        struct Bucket {
            let categoryID: UUID
            let title: String
            let symbolName: String
            let iconColor: CategoryIconColor
            var grindTotal: Decimal
            var chillTotal: Decimal
        }

        let weekRange = weekRange(for: now, calendar: calendar)
        let weeklyEntries = entriesInRange(entries, range: weekRange)

        var buckets: [UUID: Bucket] = [:]
        for entry in weeklyEntries {
            guard let category = entry.category else { continue }
            let id = category.id

            if buckets[id] == nil {
                buckets[id] = Bucket(
                    categoryID: id,
                    title: category.title,
                    symbolName: category.resolvedSymbolName,
                    iconColor: category.resolvedIconColor,
                    grindTotal: .zeroValue,
                    chillTotal: .zeroValue
                )
            }

            guard var bucket = buckets[id] else { continue }
            if entry.amountUSD >= .zeroValue {
                bucket.grindTotal = (bucket.grindTotal + entry.amountUSD).rounded(scale: 2)
            } else {
                bucket.chillTotal = (bucket.chillTotal + absolute(entry.amountUSD)).rounded(scale: 2)
            }
            buckets[id] = bucket
        }

        let grind = buckets.values
            .filter { $0.grindTotal > .zeroValue }
            .max { lhs, rhs in
                if lhs.grindTotal != rhs.grindTotal {
                    return lhs.grindTotal < rhs.grindTotal
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            }
            .map { bucket in
                WeeklyCategoryInsight(
                    categoryID: bucket.categoryID,
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.grindTotal
                )
            }

        let chill = buckets.values
            .filter { $0.chillTotal > .zeroValue }
            .max { lhs, rhs in
                if lhs.chillTotal != rhs.chillTotal {
                    return lhs.chillTotal < rhs.chillTotal
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            }
            .map { bucket in
                WeeklyCategoryInsight(
                    categoryID: bucket.categoryID,
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.chillTotal
                )
            }

        return (grind, chill)
    }

    func streakRiskAlerts(
        categories: [Category],
        entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [StreakRiskAlert] {
        var alerts: [StreakRiskAlert] = []

        for category in categories where category.resolvedStreakEnabled {
            let goal = Decimal(max(0, category.dailyGoalMinutes))
            let progress = streakService.totalProgress(for: category, on: now, entries: entries)

            switch category.resolvedType {
            case .goodHabit:
                let streak = streakService.streak(for: category, entries: entries, now: now, calendar: calendar)
                guard streak > 0, goal > .zeroValue, progress < goal else { continue }

                let remaining = (goal - progress).rounded(scale: 2)
                let ratio = goal == .zeroValue ? .zeroValue : (remaining / goal).rounded(scale: 4)
                let severity = ratio <= (Decimal(string: "0.25") ?? Decimal(0.25)) ? 3 : 2
                let message = "Needs \(formatted(remaining, unit: category.resolvedUnit)) \(category.resolvedStreakCadence.progressLabel) to protect \(streak)\(category.resolvedStreakCadence.shortSuffix) streak."

                alerts.append(
                    StreakRiskAlert(
                        id: category.id,
                        categoryID: category.id,
                        title: category.title,
                        symbolName: category.resolvedSymbolName,
                        iconColor: category.resolvedIconColor,
                        type: .goodHabit,
                        message: message,
                        severity: severity
                    )
                )

            case .quitHabit:
                guard goal > .zeroValue, progress > .zeroValue else { continue }

                let threshold70 = (goal * (Decimal(string: "0.7") ?? Decimal(0.7))).rounded(scale: 2)
                let severity: Int
                let message: String

                if progress >= goal {
                    severity = 3
                    message = "Target exceeded \(category.resolvedStreakCadence.progressLabel): \(formatted(progress, unit: category.resolvedUnit)) / \(formatted(goal, unit: category.resolvedUnit))."
                } else if progress >= threshold70 {
                    severity = 2
                    message = "Close to limit \(category.resolvedStreakCadence.progressLabel): \(formatted(progress, unit: category.resolvedUnit)) / \(formatted(goal, unit: category.resolvedUnit))."
                } else {
                    continue
                }

                alerts.append(
                    StreakRiskAlert(
                        id: category.id,
                        categoryID: category.id,
                        title: category.title,
                        symbolName: category.resolvedSymbolName,
                        iconColor: category.resolvedIconColor,
                        type: .quitHabit,
                        message: message,
                        severity: severity
                    )
                )
            }
        }

        return alerts.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.type != rhs.type {
                return lhs.type == .goodHabit
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
        let label = category.resolvedStreakCadence.progressLabel

        switch category.resolvedType {
        case .goodHabit:
            return "\(formatted(progress, unit: category.resolvedUnit))/\(thresholdText) \(label)"
        case .quitHabit:
            return progress == .zeroValue
                ? "No relapses \(label) • Target < \(thresholdText)"
                : "\(formatted(progress, unit: category.resolvedUnit)) logged \(label) • Target < \(thresholdText)"
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

    private func entriesInRange(_ entries: [Entry], range: DateInterval) -> [Entry] {
        entries.filter { entry in
            range.contains(entry.timestamp)
        }
    }

    private func weekRange(for date: Date, calendar: Calendar) -> DateInterval {
        if let week = calendar.dateInterval(of: .weekOfYear, for: date) {
            return week
        }
        guard let fallbackStart = calendar.date(byAdding: .day, value: -6, to: date) else {
            return DateInterval(start: date, end: date.addingTimeInterval(1))
        }
        return DateInterval(start: calendar.startOfDay(for: fallbackStart), end: date.addingTimeInterval(1))
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
