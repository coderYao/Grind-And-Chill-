import Foundation

struct StreakService {
    func streak(for category: Category, entries: [Entry], now: Date = .now, calendar: Calendar = .current) -> Int {
        guard category.resolvedStreakEnabled else { return 0 }

        let categoryEntries = entries.filter { entry in
            entry.category?.id == category.id
        }

        switch category.resolvedType {
        case .goodHabit:
            return goodHabitStreak(
                for: category,
                entries: categoryEntries,
                now: now,
                calendar: calendar
            )

        case .quitHabit:
            return quitHabitStreak(
                entries: categoryEntries,
                cadence: category.resolvedStreakCadence,
                now: now,
                calendar: calendar
            )
        }
    }

    func totalProgress(
        for category: Category,
        on day: Date,
        entries: [Entry],
        calendar: Calendar = .current
    ) -> Decimal {
        let range = periodRange(
            containing: day,
            cadence: category.resolvedStreakCadence,
            calendar: calendar
        )

        return entries
            .filter {
                $0.category?.id == category.id &&
                $0.timestamp >= range.start &&
                $0.timestamp < range.end
            }
            .reduce(.zeroValue) { partialResult, entry in
                partialResult + progressValue(for: entry, category: category)
            }
    }

    func totalMinutes(
        for category: Category,
        on day: Date,
        entries: [Entry],
        calendar: Calendar = .current
    ) -> Int {
        let progress = totalProgress(for: category, on: day, entries: entries, calendar: calendar)
        let wholeValue = NSDecimalNumber(decimal: progress).intValue

        switch category.resolvedUnit {
        case .time:
            return max(0, wholeValue)
        case .count, .money:
            return max(0, wholeValue)
        }
    }

    private func goodHabitStreak(
        for category: Category,
        entries: [Entry],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let cadence = category.resolvedStreakCadence
        let goal = Decimal(max(0, category.dailyGoalMinutes))
        guard goal > .zeroValue else { return 0 }

        var totalsByPeriod: [Date: Decimal] = [:]

        for entry in entries {
            let periodStart = periodAnchor(for: entry.timestamp, cadence: cadence, calendar: calendar)
            totalsByPeriod[periodStart, default: .zeroValue] += progressValue(for: entry, category: category)
        }

        let currentPeriodStart = periodAnchor(for: now, cadence: cadence, calendar: calendar)
        let hasHitGoalThisPeriod = (totalsByPeriod[currentPeriodStart] ?? .zeroValue) >= goal
        let firstCheckPeriod: Date

        if hasHitGoalThisPeriod {
            firstCheckPeriod = currentPeriodStart
        } else if let previousPeriod = previousPeriodAnchor(
            from: currentPeriodStart,
            cadence: cadence,
            calendar: calendar
        ) {
            firstCheckPeriod = previousPeriod
        } else {
            return 0
        }

        var streak = 0
        var cursor = firstCheckPeriod

        while (totalsByPeriod[cursor] ?? .zeroValue) >= goal {
            streak += 1
            guard let previous = previousPeriodAnchor(
                from: cursor,
                cadence: cadence,
                calendar: calendar
            ) else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private func quitHabitStreak(
        entries: [Entry],
        cadence: StreakCadence,
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard let lastDate = entries.map(\.timestamp).max() else {
            return 0
        }

        let start = periodAnchor(for: lastDate, cadence: cadence, calendar: calendar)
        let end = periodAnchor(for: now, cadence: cadence, calendar: calendar)
        let component: Calendar.Component
        switch cadence {
        case .daily:
            component = .day
        case .weekly:
            component = .weekOfYear
        case .monthly:
            component = .month
        }

        let periods = calendar.dateComponents([component], from: start, to: end).value(for: component) ?? 0

        return max(0, periods)
    }

    private func progressValue(for entry: Entry, category: Category) -> Decimal {
        if entry.bonusKey != nil {
            return .zeroValue
        }

        switch category.resolvedUnit {
        case .time:
            return Decimal(max(0, entry.durationMinutes))
        case .count:
            return entry.resolvedUnit == .count ? entry.resolvedQuantity : Decimal(max(0, entry.durationMinutes))
        case .money:
            if entry.amountUSD < .zeroValue {
                return entry.amountUSD * Decimal(-1)
            }
            return entry.amountUSD
        }
    }

    private func periodAnchor(for date: Date, cadence: StreakCadence, calendar: Calendar) -> Date {
        switch cadence {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func periodRange(containing date: Date, cadence: StreakCadence, calendar: Calendar) -> DateInterval {
        switch cadence {
        case .daily:
            let start = periodAnchor(for: date, cadence: .daily, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        case .weekly:
            if let range = calendar.dateInterval(of: .weekOfYear, for: date) {
                return range
            }
            return fallbackRange(for: date, cadence: .weekly, calendar: calendar)
        case .monthly:
            if let range = calendar.dateInterval(of: .month, for: date) {
                return range
            }
            return fallbackRange(for: date, cadence: .monthly, calendar: calendar)
        }
    }

    private func previousPeriodAnchor(from current: Date, cadence: StreakCadence, calendar: Calendar) -> Date? {
        switch cadence {
        case .daily:
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { return nil }
            return periodAnchor(for: previous, cadence: cadence, calendar: calendar)
        case .weekly:
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: current) else { return nil }
            return periodAnchor(for: previous, cadence: cadence, calendar: calendar)
        case .monthly:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: current) else { return nil }
            return periodAnchor(for: previous, cadence: cadence, calendar: calendar)
        }
    }

    private func fallbackRange(for date: Date, cadence: StreakCadence, calendar: Calendar) -> DateInterval {
        let start = periodAnchor(for: date, cadence: cadence, calendar: calendar)
        let end: Date

        switch cadence {
        case .daily:
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        case .weekly:
            end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start.addingTimeInterval(604_800)
        case .monthly:
            end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(2_592_000)
        }

        return DateInterval(start: start, end: end)
    }
}
