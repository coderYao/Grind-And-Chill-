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

    func totalMinutes(
        for category: Category,
        on day: Date,
        entries: [Entry],
        calendar: Calendar = .current
    ) -> Int {
        let targetDay = calendar.startOfDay(for: day)

        return entries
            .filter {
                $0.category.id == category.id &&
                calendar.isDate($0.timestamp, inSameDayAs: targetDay)
            }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    private func goodHabitStreak(
        for category: Category,
        entries: [Entry],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard category.dailyGoalMinutes > 0 else { return 0 }

        var totalsByDay: [Date: Int] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            totalsByDay[day, default: 0] += entry.durationMinutes
        }

        let today = calendar.startOfDay(for: now)
        let hasHitGoalToday = (totalsByDay[today] ?? 0) >= category.dailyGoalMinutes

        guard let firstCheckDay = calendar.date(
            byAdding: .day,
            value: hasHitGoalToday ? 0 : -1,
            to: today
        ) else {
            return 0
        }

        var streak = 0
        var cursor = firstCheckDay

        while (totalsByDay[cursor] ?? 0) >= category.dailyGoalMinutes {
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
}
