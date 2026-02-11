import Foundation

struct StreakService {
    func streak(for category: Category, entries: [Entry], now: Date = .now, calendar: Calendar = .current) -> Int {
        let categoryEntries = entries.filter { $0.category.id == category.id }

        switch category.resolvedType {
        case .goodHabit:
            return goodHabitStreak(
                for: category,
                entries: categoryEntries,
                now: now,
                calendar: calendar
            )

        case .quitHabit:
            return quitHabitStreak(entries: categoryEntries, now: now, calendar: calendar)
        }
    }

    func totalProgress(
        for category: Category,
        on day: Date,
        entries: [Entry],
        calendar: Calendar = .current
    ) -> Decimal {
        let targetDay = calendar.startOfDay(for: day)

        return entries
            .filter {
                $0.category.id == category.id &&
                calendar.isDate($0.timestamp, inSameDayAs: targetDay)
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
        let goal = Decimal(max(0, category.dailyGoalMinutes))
        guard goal > .zeroValue else { return 0 }

        var totalsByDay: [Date: Decimal] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            totalsByDay[day, default: .zeroValue] += progressValue(for: entry, category: category)
        }

        let today = calendar.startOfDay(for: now)
        let hasHitGoalToday = (totalsByDay[today] ?? .zeroValue) >= goal

        guard let firstCheckDay = calendar.date(
            byAdding: .day,
            value: hasHitGoalToday ? 0 : -1,
            to: today
        ) else {
            return 0
        }

        var streak = 0
        var cursor = firstCheckDay

        while (totalsByDay[cursor] ?? .zeroValue) >= goal {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private func quitHabitStreak(entries: [Entry], now: Date, calendar: Calendar) -> Int {
        guard let lastDate = entries.map(\.timestamp).max() else {
            return 0
        }

        let start = calendar.startOfDay(for: lastDate)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        return max(0, days)
    }

    private func progressValue(for entry: Entry, category: Category) -> Decimal {
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
}
