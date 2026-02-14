import Foundation
import SwiftData
import Testing
@testable import Grind_N_Chill

struct Grind_N_ChillTests {

    @Test
    func ledgerUsesDecimalMathAndCorrectSigns() {
        let service = LedgerService()
        let rate = Decimal(string: "20") ?? Decimal(20)

        let earned = service.earnedUSD(
            minutes: 90,
            usdPerHour: rate,
            categoryMultiplier: 1.5,
            categoryType: .goodHabit
        )

        let spent = service.earnedUSD(
            minutes: 90,
            usdPerHour: rate,
            categoryMultiplier: 1.5,
            categoryType: .quitHabit
        )

        let expectedEarned = Decimal(string: "45.00") ?? .zeroValue
        let expectedSpent = Decimal(string: "-45.00") ?? .zeroValue

        #expect(earned == expectedEarned)
        #expect(spent == expectedSpent)
    }

    @Test
    func ledgerSupportsTimeRateCountAndMoneyUnits() {
        let service = LedgerService()
        let globalRate = Decimal(string: "18") ?? Decimal(18)

        let timeByRateCategory = Category(
            title: "Consulting",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time,
            timeConversionMode: .hourlyRate,
            hourlyRateUSD: 30
        )
        let timeAmount = service.amountUSD(
            for: timeByRateCategory,
            quantity: Decimal(90),
            usdPerHour: globalRate
        )
        #expect(timeAmount == (Decimal(string: "45.00") ?? .zeroValue))

        let countCategory = Category(
            title: "Pushups",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 50,
            unit: .count,
            usdPerCount: 2.5
        )
        let countAmount = service.amountUSD(
            for: countCategory,
            quantity: Decimal(4),
            usdPerHour: globalRate
        )
        #expect(countAmount == (Decimal(string: "10.00") ?? .zeroValue))

        let moneyCategory = Category(
            title: "Impulse Spend",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 20,
            unit: .money
        )
        let moneyAmount = service.amountUSD(
            for: moneyCategory,
            quantity: Decimal(12.5),
            usdPerHour: globalRate
        )
        #expect(moneyAmount == (Decimal(string: "-12.50") ?? .zeroValue))
    }

    @Test
    @MainActor
    func manualCountEntryStoresUnitQuantityAndConvertedAmount() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Pushups",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 20,
            unit: .count,
            usdPerCount: 2.5
        )
        modelContext.insert(category)
        try modelContext.save()

        let viewModel = SessionViewModel()
        viewModel.selectedCategoryID = category.id
        viewModel.manualCount = 3

        viewModel.addManualEntry(
            categories: [category],
            existingEntries: [],
            modelContext: modelContext,
            usdPerHour: Decimal(18)
        )

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries[0].unit == .count)
        #expect(entries[0].quantity == Decimal(3))
        #expect(entries[0].durationMinutes == 0)
        #expect(entries[0].amountUSD == (Decimal(string: "7.50") ?? .zeroValue))
        #expect(viewModel.latestStatus == "Manual entry saved.")
    }

    @Test
    @MainActor
    func manualMoneyEntryUsesDirectAmountWithChillSign() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Coffee",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 15,
            unit: .money
        )
        modelContext.insert(category)
        try modelContext.save()

        let viewModel = SessionViewModel()
        viewModel.selectedCategoryID = category.id
        viewModel.manualAmountUSD = 7.25

        viewModel.addManualEntry(
            categories: [category],
            existingEntries: [],
            modelContext: modelContext,
            usdPerHour: Decimal(18)
        )

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries[0].unit == .money)
        #expect(entries[0].quantity == (Decimal(string: "7.25") ?? .zeroValue))
        #expect(entries[0].amountUSD == (Decimal(string: "-7.25") ?? .zeroValue))
        #expect(viewModel.latestStatus == "Manual entry saved.")
    }

    @Test
    @MainActor
    func manualTimeEntryUsesCustomHourlyRateWhenConfigured() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time,
            timeConversionMode: .hourlyRate,
            hourlyRateUSD: 30
        )
        modelContext.insert(category)
        try modelContext.save()

        let viewModel = SessionViewModel()
        viewModel.selectedCategoryID = category.id
        viewModel.manualMinutes = 30

        viewModel.addManualEntry(
            categories: [category],
            existingEntries: [],
            modelContext: modelContext,
            usdPerHour: Decimal(18)
        )

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries[0].unit == .time)
        #expect(entries[0].durationMinutes == 30)
        #expect(entries[0].amountUSD == (Decimal(string: "15.00") ?? .zeroValue))
        #expect(viewModel.latestStatus == "Manual entry saved.")
    }

    @Test
    @MainActor
    func startSessionRejectsNonTimeCategories() {
        let suiteName = "GrindNChill.SessionViewModel.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let category = Category(
            title: "Water",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 8,
            unit: .count,
            usdPerCount: 1
        )

        let timerManager = TimerManager(userDefaults: defaults)
        let viewModel = SessionViewModel()
        viewModel.selectedCategoryID = category.id

        viewModel.startSession(with: timerManager, categories: [category])

        #expect(timerManager.isRunning == false)
        #expect(viewModel.latestError?.contains("Time categories") == true)
    }

    @Test
    @MainActor
    func liveTimerAmountUsesElapsedSecondsAndCategorySign() {
        let viewModel = SessionViewModel()

        let grindCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        let chillCategory = Category(
            title: "Gaming",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 30,
            unit: .time
        )

        let usdPerHour = Decimal(60) // $1 per minute

        let grindAmount = viewModel.liveAmountUSD(
            for: grindCategory,
            elapsedSeconds: 90,
            usdPerHour: usdPerHour
        )
        let chillAmount = viewModel.liveAmountUSD(
            for: chillCategory,
            elapsedSeconds: 90,
            usdPerHour: usdPerHour
        )

        #expect(grindAmount == (Decimal(string: "1.50") ?? .zeroValue))
        #expect(chillAmount == (Decimal(string: "-1.50") ?? .zeroValue))
    }

    @Test
    func goodHabitStreakSkipsIncompleteTodayAndCountsPreviousDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "Deep Work",
            multiplier: 1.2,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )

        let now = date(year: 2026, month: 2, day: 10, hour: 12, minute: 0, calendar: calendar)

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 9, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 70,
                amountUSD: .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 8, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: .zeroValue,
                category: category,
                isManual: true
            )
        ]

        let streak = StreakService().streak(for: category, entries: entries, now: now, calendar: calendar)
        #expect(streak == 2)
    }

    @Test
    func quitHabitStreakUsesFullCalendarDaysSinceLastEntry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "Gaming Relapse",
            multiplier: 1,
            type: .quitHabit,
            dailyGoalMinutes: 0
        )

        let now = date(year: 2026, month: 2, day: 10, hour: 8, minute: 0, calendar: calendar)

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 7, hour: 23, minute: 30, calendar: calendar),
                durationMinutes: 20,
                amountUSD: Decimal(-5),
                category: category,
                isManual: true
            )
        ]

        let streak = StreakService().streak(for: category, entries: entries, now: now, calendar: calendar)
        #expect(streak == 3)
    }

    @Test
    @MainActor
    func dashboardDailyLedgerChangeUsesOnlyTodayEntries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar)

        let grindCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )
        let chillCategory = Category(
            title: "Snacks",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 20,
            unit: .money
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 8, minute: 15, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "10.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 9, minute: 45, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-4.00") ?? .zeroValue,
                category: chillCategory,
                isManual: true,
                quantity: Decimal(string: "4.00"),
                unit: .money
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 12, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "20.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            )
        ]

        let viewModel = DashboardViewModel()
        let change = viewModel.dailyLedgerChange(entries: entries, on: now, calendar: calendar)
        let breakdown = viewModel.dailyLedgerBreakdown(entries: entries, on: now, calendar: calendar)

        #expect(change == (Decimal(string: "6.00") ?? .zeroValue))
        #expect(breakdown.grind == (Decimal(string: "10.00") ?? .zeroValue))
        #expect(breakdown.chill == (Decimal(string: "-4.00") ?? .zeroValue))
        #expect(breakdown.entryCount == 2)
    }

    @Test
    @MainActor
    func dashboardDailyActivitiesGroupsEntriesByCategory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = date(year: 2026, month: 2, day: 11, hour: 12, minute: 0, calendar: calendar)

        let grindCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        let chillCategory = Category(
            title: "Coffee",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 15,
            unit: .money
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "9.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 45,
                amountUSD: Decimal(string: "13.50") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 11, minute: 0, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-6.00") ?? .zeroValue,
                category: chillCategory,
                isManual: true,
                quantity: Decimal(string: "6.00"),
                unit: .money
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 14, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "18.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            )
        ]

        let viewModel = DashboardViewModel()
        let activities = viewModel.dailyActivities(entries: entries, on: now, calendar: calendar)

        #expect(activities.count == 2)
        #expect(activities[0].title == "Coffee")

        let deepWork = activities.first(where: { $0.title == "Deep Work" })
        #expect(deepWork?.entryCount == 2)
        #expect(deepWork?.totalQuantity == Decimal(75))
        #expect(deepWork?.totalAmountUSD == (Decimal(string: "22.50") ?? .zeroValue))
    }

    @Test
    @MainActor
    func dashboardStreakHighlightChoosesHighestActiveStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = date(year: 2026, month: 2, day: 10, hour: 12, minute: 0, calendar: calendar)

        let grindCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )
        let chillCategory = Category(
            title: "Gaming",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 30,
            unit: .time
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "18.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 9, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "18.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 8, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "18.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 5, hour: 22, minute: 0, calendar: calendar),
                durationMinutes: 45,
                amountUSD: Decimal(string: "-12.00") ?? .zeroValue,
                category: chillCategory,
                isManual: true
            )
        ]

        let viewModel = DashboardViewModel()
        let highlight = viewModel.streakHighlight(
            categories: [grindCategory, chillCategory],
            entries: entries,
            now: now,
            calendar: calendar
        )

        #expect(highlight?.categoryID == chillCategory.id)
        #expect(highlight?.streakDays == 5)
        #expect(highlight?.type == .quitHabit)
        #expect(highlight?.progressText.contains("Target <") == true)
    }

    @Test
    @MainActor
    func historyDailySummariesIncludeNetGainAndSpent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let grindCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )
        let chillCategory = Category(
            title: "Snacks",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 15,
            unit: .money
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 12, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "15.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-4.50") ?? .zeroValue,
                category: chillCategory,
                isManual: true,
                quantity: Decimal(string: "4.50"),
                unit: .money
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 16, minute: 0, calendar: calendar),
                durationMinutes: 60,
                amountUSD: Decimal(string: "20.00") ?? .zeroValue,
                category: grindCategory,
                isManual: false
            )
        ]

        let viewModel = HistoryViewModel()
        let summaries = viewModel.dailySummaries(from: entries, calendar: calendar)

        #expect(summaries.count == 2)
        #expect(summaries[0].date == calendar.startOfDay(for: date(year: 2026, month: 2, day: 11, hour: 0, minute: 0, calendar: calendar)))
        #expect(summaries[0].ledgerChange == (Decimal(string: "10.50") ?? .zeroValue))
        #expect(summaries[0].gain == (Decimal(string: "15.00") ?? .zeroValue))
        #expect(summaries[0].spent == (Decimal(string: "4.50") ?? .zeroValue))
    }

    @Test
    @MainActor
    func historyDailySummariesRespectManualFilter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "9.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 8, minute: 30, calendar: calendar),
                durationMinutes: 15,
                amountUSD: Decimal(string: "4.50") ?? .zeroValue,
                category: category,
                isManual: true
            )
        ]

        let viewModel = HistoryViewModel()
        viewModel.showManualOnly = true

        let filtered = viewModel.filteredEntries(from: entries)
        let summaries = viewModel.dailySummaries(from: filtered, calendar: calendar)

        #expect(filtered.count == 1)
        #expect(summaries.count == 1)
        #expect(summaries[0].ledgerChange == (Decimal(string: "4.50") ?? .zeroValue))
        #expect(summaries[0].gain == (Decimal(string: "4.50") ?? .zeroValue))
        #expect(summaries[0].spent == .zeroValue)
    }

    @Test
    @MainActor
    func historyDateRangeLast7DaysFiltersOutOlderEntries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = date(year: 2026, month: 2, day: 11, hour: 12, minute: 0, calendar: calendar)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "9.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 4, hour: 18, minute: 0, calendar: calendar),
                durationMinutes: 20,
                amountUSD: Decimal(string: "6.00") ?? .zeroValue,
                category: category,
                isManual: false
            )
        ]

        let viewModel = HistoryViewModel()
        viewModel.dateRangeFilter = .last7Days
        let filtered = viewModel.filteredEntries(from: entries, now: now, calendar: calendar)

        #expect(filtered.count == 1)
        #expect(filtered[0].timestamp == date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar))
    }

    @Test
    @MainActor
    func historyDateRangeCustomUsesInclusiveDayBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "General",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 9, hour: 23, minute: 59, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "5.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 0, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "7.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 23, minute: 59, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "8.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 12, hour: 0, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "9.00") ?? .zeroValue,
                category: category,
                isManual: false
            )
        ]

        let viewModel = HistoryViewModel()
        viewModel.dateRangeFilter = .custom
        viewModel.customStartDate = date(year: 2026, month: 2, day: 10, hour: 8, minute: 0, calendar: calendar)
        viewModel.customEndDate = date(year: 2026, month: 2, day: 11, hour: 9, minute: 0, calendar: calendar)

        let filtered = viewModel.filteredEntries(from: entries, calendar: calendar)
        #expect(filtered.count == 2)
        #expect(filtered.contains(where: { $0.timestamp == date(year: 2026, month: 2, day: 10, hour: 0, minute: 0, calendar: calendar) }))
        #expect(filtered.contains(where: { $0.timestamp == date(year: 2026, month: 2, day: 11, hour: 23, minute: 59, calendar: calendar) }))
    }

    @Test
    @MainActor
    func historyChartPointsAreChronologicalAndSignedForBars() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "General",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 30
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "8.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 8, minute: 0, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-3.00") ?? .zeroValue,
                category: category,
                isManual: true
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 10, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "5.00") ?? .zeroValue,
                category: category,
                isManual: false
            )
        ]

        let viewModel = HistoryViewModel()
        let summaries = viewModel.dailySummaries(from: entries, calendar: calendar)
        let points = viewModel.chartPoints(from: summaries, dayLimit: 30)

        #expect(points.count == 2)
        #expect(points[0].date == calendar.startOfDay(for: date(year: 2026, month: 2, day: 10, hour: 0, minute: 0, calendar: calendar)))
        #expect(points[1].date == calendar.startOfDay(for: date(year: 2026, month: 2, day: 11, hour: 0, minute: 0, calendar: calendar)))
        #expect(points[1].gain == 8.0)
        #expect(points[1].spent == 3.0)
        #expect(points[1].spentAsNegative == -3.0)
        #expect(points[1].ledgerChange == 5.0)
    }

    @Test
    @MainActor
    func historyDailySummaryCSVExportIncludesExpectedColumns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 10, minute: 0, calendar: calendar),
                durationMinutes: 30,
                amountUSD: Decimal(string: "8.00") ?? .zeroValue,
                category: category,
                isManual: false
            ),
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 9, minute: 0, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-2.50") ?? .zeroValue,
                category: category,
                isManual: true,
                quantity: Decimal(string: "2.50"),
                unit: .money
            )
        ]

        let viewModel = HistoryViewModel()
        let summaries = viewModel.dailySummaries(from: entries, calendar: calendar)
        let csv = viewModel.dailySummaryCSV(from: summaries, calendar: calendar)
        let rows = csv.split(separator: "\n")

        #expect(rows.count == 2)
        #expect(rows[0] == "date,ledgerChangeUSD,gainUSD,spentUSD,entryCount")
        #expect(rows[1] == "2026-02-11,5.5,8,2.5,2")
    }

    @Test
    @MainActor
    func historyJSONExportEncodesDailySummariesAndEntries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let category = Category(
            title: "Snacks",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 15,
            unit: .money
        )

        let entries = [
            Entry(
                timestamp: date(year: 2026, month: 2, day: 11, hour: 12, minute: 0, calendar: calendar),
                durationMinutes: 0,
                amountUSD: Decimal(string: "-4.50") ?? .zeroValue,
                category: category,
                note: "Afternoon snack",
                isManual: true,
                quantity: Decimal(string: "4.50"),
                unit: .money
            )
        ]

        let viewModel = HistoryViewModel()
        let summaries = viewModel.dailySummaries(from: entries, calendar: calendar)
        let json = try viewModel.exportJSON(from: summaries, manualOnlyFilter: true, calendar: calendar)
        let data = Data(json.utf8)
        let payload = try JSONDecoder().decode(HistoryViewModel.ExportPayload.self, from: data)

        #expect(payload.manualOnlyFilter == true)
        #expect(payload.dateRangeFilter == HistoryViewModel.DateRangeFilter.all.rawValue)
        #expect(payload.dailySummaries.count == 1)
        #expect(payload.entries.count == 1)
        #expect(payload.dailySummaries[0].date == "2026-02-11")
        #expect(payload.dailySummaries[0].ledgerChangeUSD == "-4.5")
        #expect(payload.entries[0].categoryTitle == "Snacks")
        #expect(payload.entries[0].unit == CategoryUnit.money.rawValue)
        #expect(payload.entries[0].isManual == true)
    }

    @Test
    @MainActor
    func historyManualEditRecalculatesAmountAndSavesNote() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Coffee",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 15,
            unit: .money
        )
        modelContext.insert(category)

        let entry = Entry(
            timestamp: Date(timeIntervalSinceReferenceDate: 100_000),
            durationMinutes: 0,
            amountUSD: Decimal(string: "-4.50") ?? .zeroValue,
            category: category,
            note: "old note",
            isManual: true,
            quantity: Decimal(string: "4.50"),
            unit: .money
        )
        modelContext.insert(entry)
        try modelContext.save()

        let suiteName = "GrindNChill.HistoryEdit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = HistoryViewModel(
            importUndoStore: HistoryImportUndoStore(userDefaults: defaults),
            deleteUndoStore: HistoryDeleteUndoStore(userDefaults: defaults)
        )
        guard var draft = viewModel.manualDraft(for: entry) else {
            Issue.record("Expected manual draft.")
            return
        }
        draft.amountInput = 6.75
        draft.note = "updated note"

        let saved = viewModel.saveManualEdit(
            draft,
            entries: [entry],
            modelContext: modelContext,
            usdPerHour: Decimal(18)
        )
        #expect(saved == true)

        let persistedEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(persistedEntries.count == 1)
        #expect(persistedEntries[0].amountUSD == (Decimal(string: "-6.75") ?? .zeroValue))
        #expect(persistedEntries[0].quantity == (Decimal(string: "6.75") ?? .zeroValue))
        #expect(persistedEntries[0].note == "updated note")
        #expect(viewModel.latestStatus == "Manual entry updated.")
    }

    @Test
    @MainActor
    func historyDeleteUndoRestoresDeletedEntry() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        modelContext.insert(category)

        let deletedID = UUID()
        let keptID = UUID()
        let deletedEntry = Entry(
            id: deletedID,
            timestamp: Date(timeIntervalSinceReferenceDate: 101_000),
            durationMinutes: 45,
            amountUSD: Decimal(string: "13.50") ?? .zeroValue,
            category: category,
            note: "delete me",
            isManual: true,
            quantity: Decimal(45),
            unit: .time
        )
        let keptEntry = Entry(
            id: keptID,
            timestamp: Date(timeIntervalSinceReferenceDate: 101_100),
            durationMinutes: 30,
            amountUSD: Decimal(string: "9.00") ?? .zeroValue,
            category: category,
            isManual: false
        )
        modelContext.insert(deletedEntry)
        modelContext.insert(keptEntry)
        try modelContext.save()

        let suiteName = "GrindNChill.HistoryDeleteUndo.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let viewModel = HistoryViewModel(
            importUndoStore: HistoryImportUndoStore(userDefaults: defaults),
            deleteUndoStore: HistoryDeleteUndoStore(userDefaults: defaults)
        )

        viewModel.deleteEntries(
            at: IndexSet(integer: 0),
            from: [deletedEntry, keptEntry],
            modelContext: modelContext
        )
        #expect(viewModel.canUndoLastDelete == true)

        let entriesAfterDelete = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entriesAfterDelete.count == 1)
        #expect(entriesAfterDelete[0].id == keptID)

        viewModel.undoLastDelete(modelContext: modelContext)
        #expect(viewModel.canUndoLastDelete == false)

        let entriesAfterUndo = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entriesAfterUndo.count == 2)
        #expect(entriesAfterUndo.contains(where: { $0.id == deletedID }))

        guard let restored = entriesAfterUndo.first(where: { $0.id == deletedID }) else {
            Issue.record("Expected restored entry.")
            return
        }
        #expect(restored.note == "delete me")
        #expect(restored.amountUSD == (Decimal(string: "13.5") ?? .zeroValue))
        #expect(restored.quantity == Decimal(45))
    }

    @Test
    @MainActor
    func historyJSONImportPreviewReportsCreateUpdateAndSkippedCounts() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let existingCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        modelContext.insert(existingCategory)

        let existingID = UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID()
        let existingEntry = Entry(
            id: existingID,
            timestamp: Date(timeIntervalSinceReferenceDate: 20_000),
            durationMinutes: 30,
            amountUSD: Decimal(string: "9.00") ?? .zeroValue,
            category: existingCategory,
            note: "Existing",
            isManual: false
        )
        modelContext.insert(existingEntry)
        try modelContext.save()

        let payload = """
        {
          "entries": [
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "timestamp": "2026-02-13T12:00:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "45",
              "durationMinutes": 45,
              "amountUSD": "13.50",
              "isManual": true,
              "note": "Will update"
            },
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "timestamp": "2026-02-13T12:30:00Z",
              "categoryTitle": "Coffee",
              "categoryType": "quitHabit",
              "unit": "money",
              "quantity": "4.00",
              "durationMinutes": 0,
              "amountUSD": "4.00",
              "isManual": true,
              "note": "Will create"
            },
            {
              "id": "not-a-uuid",
              "timestamp": "2026-02-13T13:00:00Z",
              "categoryTitle": "Ignore",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "10",
              "durationMinutes": 10,
              "amountUSD": "3.00",
              "isManual": false,
              "note": "Invalid ID"
            }
          ]
        }
        """

        let preview = try HistoryImportService.previewJSON(
            data: Data(payload.utf8),
            modelContext: modelContext
        )

        #expect(preview.processedEntries == 3)
        #expect(preview.entriesToCreate == 1)
        #expect(preview.entriesToUpdate == 1)
        #expect(preview.categoriesToCreate == 1)
        #expect(preview.skippedEntries == 1)
        #expect(preview.hasChanges == true)
    }

    @Test
    @MainActor
    func historyJSONImportPreviewTreatsDuplicatePayloadIDAsCreateThenUpdate() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let payload = """
        {
          "entries": [
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "timestamp": "2026-02-13T10:00:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "20",
              "durationMinutes": 20,
              "amountUSD": "6.00",
              "isManual": false,
              "note": "First"
            },
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "timestamp": "2026-02-13T11:00:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "25",
              "durationMinutes": 25,
              "amountUSD": "7.50",
              "isManual": true,
              "note": "Second"
            }
          ]
        }
        """

        let preview = try HistoryImportService.previewJSON(
            data: Data(payload.utf8),
            modelContext: modelContext
        )

        #expect(preview.processedEntries == 2)
        #expect(preview.entriesToCreate == 1)
        #expect(preview.entriesToUpdate == 1)
        #expect(preview.categoriesToCreate == 1)
        #expect(preview.skippedEntries == 0)
    }

    @Test
    @MainActor
    func historyJSONImportCreatesEntriesAndNormalizesChillAmounts() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let payload = """
        {
          "entries": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "timestamp": "2026-02-13T18:10:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "45",
              "durationMinutes": 45,
              "amountUSD": "13.50",
              "isManual": false,
              "note": "Focus block"
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "timestamp": "2026-02-13T19:00:00Z",
              "categoryTitle": "Snacks",
              "categoryType": "quitHabit",
              "unit": "money",
              "quantity": "6.25",
              "durationMinutes": 0,
              "amountUSD": "6.25",
              "isManual": true,
              "note": "Late snack"
            }
          ]
        }
        """

        let report = try HistoryImportService.importJSON(
            data: Data(payload.utf8),
            modelContext: modelContext
        )
        #expect(report.processedEntries == 2)
        #expect(report.createdEntries == 2)
        #expect(report.updatedEntries == 0)
        #expect(report.skippedEntries == 0)
        #expect(report.createdCategories == 2)

        let categories = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        #expect(categories.count == 2)

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 2)

        guard let chillEntry = entries.first(where: { $0.id.uuidString == "22222222-2222-2222-2222-222222222222" }) else {
            Issue.record("Expected imported chill entry.")
            return
        }

        #expect(chillEntry.amountUSD == (Decimal(string: "-6.25") ?? .zeroValue))
        #expect(chillEntry.resolvedQuantity == (Decimal(string: "6.25") ?? .zeroValue))
        #expect(chillEntry.resolvedUnit == .money)
        #expect(chillEntry.category?.resolvedType == .quitHabit)
    }

    @Test
    @MainActor
    func historyJSONImportUpsertsExistingEntriesByID() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        modelContext.insert(category)

        let existingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        let existingEntry = Entry(
            id: existingID,
            timestamp: Date(timeIntervalSinceReferenceDate: 10_000),
            durationMinutes: 20,
            amountUSD: Decimal(string: "6.00") ?? .zeroValue,
            category: category,
            note: "Old note",
            isManual: false,
            quantity: Decimal(20),
            unit: .time
        )
        modelContext.insert(existingEntry)
        try modelContext.save()

        let payload = """
        {
          "entries": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "timestamp": "2026-02-13T21:30:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "35",
              "durationMinutes": 35,
              "amountUSD": "10.50",
              "isManual": true,
              "note": "Updated note"
            }
          ]
        }
        """

        let report = try HistoryImportService.importJSON(
            data: Data(payload.utf8),
            modelContext: modelContext
        )
        #expect(report.processedEntries == 1)
        #expect(report.createdEntries == 0)
        #expect(report.updatedEntries == 1)
        #expect(report.skippedEntries == 0)
        #expect(report.createdCategories == 0)

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries[0].id == existingID)
        #expect(entries[0].durationMinutes == 35)
        #expect(entries[0].amountUSD == (Decimal(string: "10.5") ?? .zeroValue))
        #expect(entries[0].isManual == true)
        #expect(entries[0].note == "Updated note")
    }

    @Test
    @MainActor
    func historyJSONImportKeepExistingPolicySkipsConflictingEntries() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        modelContext.insert(category)

        let existingID = UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID()
        let existingEntry = Entry(
            id: existingID,
            timestamp: Date(timeIntervalSinceReferenceDate: 50_000),
            durationMinutes: 20,
            amountUSD: Decimal(string: "6.00") ?? .zeroValue,
            category: category,
            note: "Keep me",
            isManual: false,
            quantity: Decimal(20),
            unit: .time
        )
        modelContext.insert(existingEntry)
        try modelContext.save()

        let payload = """
        {
          "entries": [
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "timestamp": "2026-02-13T22:30:00Z",
              "categoryTitle": "Brand New Category",
              "categoryType": "quitHabit",
              "unit": "money",
              "quantity": "10.50",
              "durationMinutes": 0,
              "amountUSD": "10.50",
              "isManual": true,
              "note": "Should be ignored"
            }
          ]
        }
        """

        let report = try HistoryImportService.importJSON(
            data: Data(payload.utf8),
            modelContext: modelContext,
            conflictPolicy: .keepExisting
        )
        #expect(report.processedEntries == 1)
        #expect(report.createdEntries == 0)
        #expect(report.updatedEntries == 0)
        #expect(report.skippedEntries == 1)
        #expect(report.createdCategories == 0)

        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        let categories = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        #expect(entries.count == 1)
        #expect(categories.count == 1)
        #expect(entries[0].id == existingID)
        #expect(entries[0].durationMinutes == 20)
        #expect(entries[0].amountUSD == (Decimal(string: "6.0") ?? .zeroValue))
        #expect(entries[0].isManual == false)
        #expect(entries[0].note == "Keep me")
    }

    @Test
    @MainActor
    func historyJSONImportUndoRevertsCreatedAndUpdatedRecords() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let existingCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        modelContext.insert(existingCategory)

        let existingID = UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID()
        let originalTimestamp = Date(timeIntervalSinceReferenceDate: 70_000)
        let existingEntry = Entry(
            id: existingID,
            timestamp: originalTimestamp,
            durationMinutes: 20,
            amountUSD: Decimal(string: "6.00") ?? .zeroValue,
            category: existingCategory,
            note: "Original",
            isManual: false,
            quantity: Decimal(20),
            unit: .time
        )
        modelContext.insert(existingEntry)
        try modelContext.save()

        let payload = """
        {
          "entries": [
            {
              "id": "88888888-8888-8888-8888-888888888888",
              "timestamp": "2026-02-13T09:30:00Z",
              "categoryTitle": "Deep Work",
              "categoryType": "goodHabit",
              "unit": "time",
              "quantity": "40",
              "durationMinutes": 40,
              "amountUSD": "12.00",
              "isManual": true,
              "note": "Updated"
            },
            {
              "id": "99999999-9999-9999-9999-999999999999",
              "timestamp": "2026-02-13T11:00:00Z",
              "categoryTitle": "Coffee",
              "categoryType": "quitHabit",
              "unit": "money",
              "quantity": "5.50",
              "durationMinutes": 0,
              "amountUSD": "5.50",
              "isManual": true,
              "note": "Created"
            }
          ]
        }
        """

        let importReport = try HistoryImportService.importJSON(
            data: Data(payload.utf8),
            modelContext: modelContext
        )
        #expect(importReport.createdEntries == 1)
        #expect(importReport.updatedEntries == 1)
        #expect(importReport.createdCategories == 1)
        #expect(importReport.undoPayload != nil)

        guard let undoPayload = importReport.undoPayload else {
            Issue.record("Expected undo payload after import.")
            return
        }

        let undoReport = try HistoryImportService.undoImport(undoPayload, modelContext: modelContext)
        #expect(undoReport.removedCreatedEntries == 1)
        #expect(undoReport.revertedUpdatedEntries == 1)
        #expect(undoReport.removedCreatedCategories == 1)
        #expect(undoReport.missingRecords == 0)

        let categoriesAfterUndo = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        #expect(categoriesAfterUndo.count == 1)
        #expect(categoriesAfterUndo[0].title == "Deep Work")

        let entriesAfterUndo = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(entriesAfterUndo.count == 1)
        #expect(entriesAfterUndo[0].id == existingID)
        #expect(entriesAfterUndo[0].timestamp == originalTimestamp)
        #expect(entriesAfterUndo[0].durationMinutes == 20)
        #expect(entriesAfterUndo[0].amountUSD == (Decimal(string: "6.0") ?? .zeroValue))
        #expect(entriesAfterUndo[0].note == "Original")
        #expect(entriesAfterUndo[0].isManual == false)
        #expect(entriesAfterUndo[0].unit == .time)
        #expect(entriesAfterUndo[0].category?.id == existingCategory.id)
    }

    @Test
    @MainActor
    func timerManagerRestoresPersistedSessionAndClearsOnStop() {
        let suiteName = "GrindNChill.TimerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let startTime = date(year: 2026, month: 2, day: 10, hour: 10, minute: 0, calendar: calendar)
        let categoryID = UUID()

        let manager = TimerManager(userDefaults: defaults)
        #expect(manager.isRunning == false)

        manager.start(categoryID: categoryID, at: startTime)
        #expect(manager.activeCategoryID == categoryID)
        #expect(manager.startTime == startTime)

        let restored = TimerManager(userDefaults: defaults)
        #expect(restored.activeCategoryID == categoryID)
        #expect(restored.startTime == startTime)
        #expect(restored.elapsedSeconds(at: startTime.addingTimeInterval(125)) == 125)

        let completed = restored.stop(at: startTime.addingTimeInterval(125))
        #expect(completed?.elapsedSeconds == 125)
        #expect(restored.isRunning == false)

        #expect(defaults.string(forKey: AppStorageKeys.activeCategoryID) == nil)
        #expect(defaults.object(forKey: AppStorageKeys.activeStartTime) == nil)

        let reset = TimerManager(userDefaults: defaults)
        #expect(reset.isRunning == false)
    }

    @Test
    @MainActor
    func badgeAwardsAreIdempotentWithinSameDay() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = date(year: 2026, month: 2, day: 10, hour: 12, minute: 0, calendar: calendar)

        let category = Category(
            title: "Deep Work",
            multiplier: 1.2,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            symbolName: "brain.head.profile"
        )
        modelContext.insert(category)

        var entries: [Entry] = []
        for dayOffset in 0 ..< 7 {
            let timestamp = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let entry = Entry(
                timestamp: timestamp,
                durationMinutes: 60,
                amountUSD: Decimal(5),
                category: category,
                isManual: false
            )
            modelContext.insert(entry)
            entries.append(entry)
        }
        try modelContext.save()

        var badgeService = BadgeService()
        badgeService.milestones = [3, 7]

        let firstAwards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        #expect(firstAwards.count == 2)
        try modelContext.save()

        let secondAwards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        #expect(secondAwards.isEmpty)

        let awardCount = try modelContext.fetchCount(FetchDescriptor<BadgeAward>())
        #expect(awardCount == 2)
    }

    @Test
    @MainActor
    func badgesRespectCategoryConfiguration() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = date(year: 2026, month: 2, day: 10, hour: 12, minute: 0, calendar: calendar)

        let category = Category(
            title: "Configured Badges",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            badgeMilestones: "2,4",
            streakBonusEnabled: true,
            streakBonusSchedule: "2:1.25,4:3.50"
        )
        modelContext.insert(category)

        var entries: [Entry] = []
        for dayOffset in 0 ..< 4 {
            let timestamp = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let entry = Entry(
                timestamp: timestamp,
                durationMinutes: 60,
                amountUSD: Decimal(5),
                category: category,
                isManual: false
            )
            modelContext.insert(entry)
            entries.append(entry)
        }
        try modelContext.save()

        var badgeService = BadgeService()
        badgeService.milestones = [3, 7, 30]

        let awards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )

        #expect(awards.count == 2)
        let allEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        let bonusEntries = allEntries.filter { $0.bonusKey != nil }
        #expect(bonusEntries.count == 2)
        let bonusAmounts = Set(bonusEntries.map { NSDecimalNumber(decimal: $0.amountUSD).stringValue })
        #expect(bonusAmounts == Set(["1.25", "3.5"]))

        category.badgeEnabled = false
        let disabledAwards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        #expect(disabledAwards.isEmpty)
        let entriesAfterDisableBadge = try modelContext.fetch(FetchDescriptor<Entry>())
        let bonusAfterDisableBadge = entriesAfterDisableBadge.filter { $0.bonusKey != nil }
        #expect(bonusAfterDisableBadge.count == 2)

        category.badgeEnabled = true
        category.streakEnabled = false
        let streakDisabledAwards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        #expect(streakDisabledAwards.isEmpty)

        category.streakEnabled = true
        category.badgeEnabled = false
        category.streakBonusEnabled = false
        let noRewardAwards = try badgeService.awardBadgesIfNeeded(
            for: category,
            entries: entries,
            modelContext: modelContext,
            now: now,
            calendar: calendar
        )
        #expect(noRewardAwards.isEmpty)
    }

    @Test
    @MainActor
    func deletingActiveCategoryIsBlocked() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let deepWork = Category(
            title: "Deep Work",
            multiplier: 1.2,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            symbolName: "brain.head.profile"
        )
        let reading = Category(
            title: "Reading",
            multiplier: 1.1,
            type: .goodHabit,
            dailyGoalMinutes: 45,
            symbolName: "book.fill"
        )

        modelContext.insert(deepWork)
        modelContext.insert(reading)
        try modelContext.save()

        let viewModel = CategoriesViewModel()
        viewModel.deleteCategories(
            at: IndexSet(integer: 0),
            from: [deepWork, reading],
            modelContext: modelContext,
            activeCategoryID: deepWork.id
        )

        let countAfterBlockedDelete = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(countAfterBlockedDelete == 2)
        #expect(viewModel.latestError?.contains("Stop the active session") == true)

        viewModel.deleteCategories(
            at: IndexSet(integer: 1),
            from: [deepWork, reading],
            modelContext: modelContext,
            activeCategoryID: deepWork.id
        )

        let countAfterAllowedDelete = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(countAfterAllowedDelete == 1)
    }

    @Test
    @MainActor
    func deletingCategoryCanBeUndoneWithEntries() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let deepWork = Category(
            title: "Deep Work",
            multiplier: 1.2,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            symbolName: "brain.head.profile",
            iconColor: .blue,
            unit: .time
        )
        let reading = Category(
            title: "Reading",
            multiplier: 1.1,
            type: .goodHabit,
            dailyGoalMinutes: 45,
            symbolName: "book.fill",
            unit: .time
        )
        modelContext.insert(deepWork)
        modelContext.insert(reading)

        let deletedEntryID = UUID()
        modelContext.insert(
            Entry(
                id: deletedEntryID,
                timestamp: Date(timeIntervalSinceReferenceDate: 90_000),
                durationMinutes: 40,
                amountUSD: Decimal(string: "12.00") ?? .zeroValue,
                category: deepWork,
                note: "Restore me",
                bonusKey: "bonus:1",
                isManual: true,
                quantity: Decimal(40),
                unit: .time
            )
        )
        modelContext.insert(
            Entry(
                timestamp: Date(timeIntervalSinceReferenceDate: 90_100),
                durationMinutes: 20,
                amountUSD: Decimal(string: "6.00") ?? .zeroValue,
                category: reading,
                isManual: false
            )
        )
        try modelContext.save()

        let viewModel = CategoriesViewModel()
        viewModel.deleteCategories(
            at: IndexSet(integer: 0),
            from: [deepWork, reading],
            modelContext: modelContext,
            activeCategoryID: nil
        )

        #expect(viewModel.canUndoLastDeletion == true)

        let categoriesAfterDelete = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        let entriesAfterDelete = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(categoriesAfterDelete.count == 1)
        #expect(entriesAfterDelete.count == 1)
        #expect(categoriesAfterDelete[0].title == "Reading")

        viewModel.undoLastDeletedCategories(in: modelContext)
        #expect(viewModel.canUndoLastDeletion == false)

        let categoriesAfterUndo = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        let entriesAfterUndo = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(categoriesAfterUndo.count == 2)
        #expect(entriesAfterUndo.count == 2)

        guard let restoredCategory = categoriesAfterUndo.first(where: { $0.id == deepWork.id }) else {
            Issue.record("Expected deleted category to be restored.")
            return
        }
        #expect(restoredCategory.title == "Deep Work")
        #expect(restoredCategory.resolvedIconColor == .blue)

        guard let restoredEntry = entriesAfterUndo.first(where: { $0.id == deletedEntryID }) else {
            Issue.record("Expected deleted entry to be restored.")
            return
        }
        #expect(restoredEntry.category?.id == deepWork.id)
        #expect(restoredEntry.note == "Restore me")
        #expect(restoredEntry.bonusKey == "bonus:1")
        #expect(restoredEntry.durationMinutes == 40)
        #expect(restoredEntry.amountUSD == (Decimal(string: "12.0") ?? .zeroValue))
    }

    @Test
    @MainActor
    func categoryDeleteUndoPersistsAcrossViewModelRecreation() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let suiteName = "GrindNChill.CategoryDeleteUndo.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated UserDefaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let undoStore = CategoryDeleteUndoStore(userDefaults: defaults)

        let deletedCategory = Category(
            title: "Writing",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 30,
            unit: .time
        )
        let keptCategory = Category(
            title: "Reading",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 20,
            unit: .time
        )
        modelContext.insert(deletedCategory)
        modelContext.insert(keptCategory)

        let deletedEntryID = UUID()
        modelContext.insert(
            Entry(
                id: deletedEntryID,
                timestamp: Date(timeIntervalSinceReferenceDate: 91_000),
                durationMinutes: 25,
                amountUSD: Decimal(string: "7.50") ?? .zeroValue,
                category: deletedCategory,
                note: "persist me",
                isManual: true
            )
        )
        try modelContext.save()

        let firstViewModel = CategoriesViewModel(deleteUndoStore: undoStore)
        firstViewModel.deleteCategories(
            at: IndexSet(integer: 0),
            from: [deletedCategory, keptCategory],
            modelContext: modelContext,
            activeCategoryID: nil
        )
        #expect(firstViewModel.canUndoLastDeletion == true)

        let secondViewModel = CategoriesViewModel(deleteUndoStore: undoStore)
        #expect(secondViewModel.canUndoLastDeletion == true)
        secondViewModel.undoLastDeletedCategories(in: modelContext)

        let categoriesAfterUndo = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        let entriesAfterUndo = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(categoriesAfterUndo.count == 2)
        #expect(entriesAfterUndo.contains(where: { $0.id == deletedEntryID }))

        let thirdViewModel = CategoriesViewModel(deleteUndoStore: undoStore)
        #expect(thirdViewModel.canUndoLastDeletion == false)
    }

    @Test
    @MainActor
    func creatingAndEditingCategoryPersists() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let viewModel = CategoriesViewModel()
        viewModel.beginCreating()
        viewModel.title = "Writing"
        viewModel.multiplier = 1.25
        viewModel.type = .goodHabit
        viewModel.iconColor = .teal
        viewModel.dailyGoalMinutes = 75
        viewModel.streakEnabled = true
        viewModel.badgeEnabled = true
        viewModel.badgeMilestonesInput = "3, 10, 20"
        viewModel.streakBonusEnabled = true
        viewModel.setStreakBonusAmount(4.5, for: 3)
        viewModel.setStreakBonusAmount(8.0, for: 10)
        viewModel.setStreakBonusAmount(12.25, for: 20)

        let created = viewModel.saveCategory(in: modelContext, existingCategories: [])
        #expect(created == true)

        let categoriesAfterCreate = try modelContext.fetch(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(categoriesAfterCreate.count == 1)
        #expect(categoriesAfterCreate.first?.title == "Writing")

        guard let savedCategory = categoriesAfterCreate.first else {
            Issue.record("Expected one created category.")
            return
        }

        let createdBonusSchedule = savedCategory.resolvedStreakBonusAmounts(defaultMilestones: [3, 10, 20])
        #expect(createdBonusSchedule[3] == Decimal(string: "4.5"))
        #expect(createdBonusSchedule[10] == Decimal(string: "8"))
        #expect(createdBonusSchedule[20] == Decimal(string: "12.25"))

        viewModel.beginEditing(savedCategory)
        viewModel.title = "Writing Sprint"
        viewModel.multiplier = 1.4
        viewModel.iconColor = .pink
        viewModel.dailyGoalMinutes = 90
        viewModel.streakEnabled = false
        viewModel.badgeEnabled = true
        viewModel.badgeMilestonesInput = "5, 9"
        viewModel.streakBonusEnabled = true
        viewModel.setStreakBonusAmount(9, for: 5)
        viewModel.setStreakBonusAmount(11, for: 9)

        let updated = viewModel.saveCategory(
            in: modelContext,
            existingCategories: categoriesAfterCreate
        )
        #expect(updated == true)

        let categoriesAfterEdit = try modelContext.fetch(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(categoriesAfterEdit.count == 1)
        #expect(categoriesAfterEdit.first?.title == "Writing Sprint")
        #expect(categoriesAfterEdit.first?.multiplier == 1.4)
        #expect(categoriesAfterEdit.first?.dailyGoalMinutes == 90)
        #expect(categoriesAfterEdit.first?.iconColor == .pink)
        #expect(categoriesAfterEdit.first?.resolvedStreakEnabled == false)
        #expect(categoriesAfterEdit.first?.resolvedBadgeEnabled == false)
        #expect(categoriesAfterEdit.first?.resolvedStreakBonusEnabled == false)
    }

    @Test
    @MainActor
    func creatingCountCategoryPersistsUnitAndValuePerCount() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let viewModel = CategoriesViewModel()
        viewModel.beginCreating()
        viewModel.title = "Water Cups"
        viewModel.type = .goodHabit
        viewModel.unit = .count
        viewModel.usdPerCount = 1.75
        viewModel.dailyGoalMinutes = 8

        let saved = viewModel.saveCategory(in: modelContext, existingCategories: [])
        #expect(saved == true)

        let categories = try modelContext.fetch(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(categories.count == 1)
        #expect(categories[0].resolvedUnit == .count)
        #expect(categories[0].usdPerCount == 1.75)
    }

    @Test
    @MainActor
    func categorySeederSeedsOnceOnlyWhenEmpty() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        try CategorySeeder.seedIfNeeded(in: modelContext)
        let firstSeedCount = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(firstSeedCount == 3)

        try CategorySeeder.seedIfNeeded(in: modelContext)
        let secondSeedCount = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(secondSeedCount == 3)
    }

    @Test
    @MainActor
    func legacyCategoryRepairBackfillsInvalidFields() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let legacyCategory = Category(
            title: "Legacy",
            multiplier: 1.2,
            type: .goodHabit,
            dailyGoalMinutes: 25,
            symbolName: nil
        )
        legacyCategory.type = nil
        legacyCategory.multiplier = 0
        legacyCategory.dailyGoalMinutes = -10
        legacyCategory.symbolName = "invalid.symbol"
        modelContext.insert(legacyCategory)
        try modelContext.save()

        let repairedCount = try LegacyDataRepairService.repairCategoriesIfNeeded(in: modelContext)
        #expect(repairedCount == 1)

        let fetched = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        #expect(fetched.count == 1)
        #expect(fetched[0].resolvedType == .goodHabit)
        #expect(fetched[0].resolvedUnit == .time)
        #expect(fetched[0].multiplier == 1)
        #expect(fetched[0].dailyGoalMinutes == 0)
        #expect(fetched[0].resolvedStreakEnabled == true)
        #expect(fetched[0].resolvedBadgeEnabled == true)
        #expect(fetched[0].resolvedStreakBonusEnabled == false)
        #expect(fetched[0].symbolName == CategorySymbolCatalog.defaultSymbol(for: .goodHabit))
    }

    @Test
    @MainActor
    func migrationBackfillRepairsEntriesBadgesAndSyncEvents() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let chillCategory = Category(
            title: "Coffee",
            multiplier: 1.0,
            type: .quitHabit,
            dailyGoalMinutes: 10,
            unit: .money
        )
        modelContext.insert(chillCategory)

        let chillEntry = Entry(
            timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
            durationMinutes: -5,
            amountUSD: Decimal(string: "7.50") ?? .zeroValue,
            category: chillCategory,
            note: "  Chill note  ",
            bonusKey: "   ",
            isManual: true,
            quantity: Decimal(-1),
            unit: nil
        )
        let timedEntry = Entry(
            timestamp: Date(timeIntervalSinceReferenceDate: 2_100),
            durationMinutes: 12,
            amountUSD: Decimal(string: "3.00") ?? .zeroValue,
            category: nil,
            note: "  ",
            isManual: false,
            quantity: nil,
            unit: nil
        )
        modelContext.insert(chillEntry)
        modelContext.insert(timedEntry)

        let olderAwardDate = Date(timeIntervalSinceReferenceDate: 3_000)
        let newerAwardDate = Date(timeIntervalSinceReferenceDate: 3_100)
        modelContext.insert(
            BadgeAward(
                awardKey: " streak:coffee:3:2026-02-13 ",
                dateAwarded: newerAwardDate
            )
        )
        modelContext.insert(
            BadgeAward(
                awardKey: "streak:coffee:3:2026-02-13",
                dateAwarded: olderAwardDate
            )
        )

        let startedAt = Date(timeIntervalSinceReferenceDate: 4_000)
        modelContext.insert(
            SyncEventHistory(
                eventIdentifier: "event-dup",
                kindRaw: "Import",
                outcomeRaw: "success",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(10),
                detail: nil,
                recordedAt: startedAt.addingTimeInterval(10)
            )
        )
        modelContext.insert(
            SyncEventHistory(
                eventIdentifier: "event-dup",
                kindRaw: "Export",
                outcomeRaw: "success",
                startedAt: startedAt.addingTimeInterval(20),
                endedAt: startedAt.addingTimeInterval(30),
                detail: "latest",
                recordedAt: startedAt.addingTimeInterval(40)
            )
        )
        modelContext.insert(
            SyncEventHistory(
                eventIdentifier: "event-needs-normalization",
                kindRaw: " ",
                outcomeRaw: " ",
                startedAt: startedAt.addingTimeInterval(60),
                endedAt: startedAt.addingTimeInterval(30),
                detail: "   ",
                recordedAt: startedAt.addingTimeInterval(20)
            )
        )

        try modelContext.save()
        try GrindNChillMigrationPlan.applyPostMigrationDefaultsForTesting(in: modelContext)

        let repairedEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        #expect(repairedEntries.count == 2)

        guard let repairedChillEntry = repairedEntries.first(where: { $0.id == chillEntry.id }) else {
            Issue.record("Expected repaired chill entry to exist.")
            return
        }
        #expect(repairedChillEntry.durationMinutes == 0)
        #expect(repairedChillEntry.note == "Chill note")
        #expect(repairedChillEntry.bonusKey == nil)
        #expect(repairedChillEntry.unit == .money)
        #expect(repairedChillEntry.amountUSD == (Decimal(string: "-7.50") ?? .zeroValue))
        #expect(repairedChillEntry.quantity == (Decimal(string: "7.50") ?? .zeroValue))

        guard let repairedTimedEntry = repairedEntries.first(where: { $0.id == timedEntry.id }) else {
            Issue.record("Expected repaired timed entry to exist.")
            return
        }
        #expect(repairedTimedEntry.unit == .time)
        #expect(repairedTimedEntry.quantity == Decimal(12))
        #expect(repairedTimedEntry.note.isEmpty)

        let repairedAwards = try modelContext.fetch(FetchDescriptor<BadgeAward>())
        #expect(repairedAwards.count == 1)
        #expect(repairedAwards[0].awardKey == "streak:coffee:3:2026-02-13")
        #expect(repairedAwards[0].dateAwarded == olderAwardDate)

        let repairedEvents = try modelContext.fetch(FetchDescriptor<SyncEventHistory>())
        #expect(repairedEvents.count == 2)

        guard let dedupedEvent = repairedEvents.first(where: { $0.eventIdentifier == "event-dup" }) else {
            Issue.record("Expected deduplicated sync event to exist.")
            return
        }
        #expect(dedupedEvent.kindRaw == "Export")
        #expect(dedupedEvent.recordedAt == startedAt.addingTimeInterval(40))

        guard let normalizedEvent = repairedEvents.first(where: { $0.eventIdentifier == "event-needs-normalization" }) else {
            Issue.record("Expected normalized sync event to exist.")
            return
        }
        #expect(normalizedEvent.kindRaw == "Sync")
        #expect(normalizedEvent.outcomeRaw == "inProgress")
        #expect(normalizedEvent.endedAt == normalizedEvent.startedAt)
        #expect(normalizedEvent.recordedAt == normalizedEvent.startedAt)
        #expect(normalizedEvent.detail == nil)
    }

    @Test
    @MainActor
    func syncConflictResolverMergesDuplicateCategoriesAndKeepsEntries() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let firstCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            unit: .time
        )
        let duplicateCategory = Category(
            title: "Deep Work",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 60,
            symbolName: "brain.head.profile",
            iconColor: .blue,
            unit: .time
        )
        let duplicateEntry = Entry(
            timestamp: Date.now,
            durationMinutes: 30,
            amountUSD: Decimal(string: "9.00") ?? .zeroValue,
            category: duplicateCategory,
            isManual: false
        )

        modelContext.insert(firstCategory)
        modelContext.insert(duplicateCategory)
        modelContext.insert(duplicateEntry)
        try modelContext.save()

        let report = try SyncConflictResolverService.resolveConflictsIfNeeded(in: modelContext)
        let categories = try modelContext.fetch(FetchDescriptor<Grind_N_Chill.Category>())
        let entries = try modelContext.fetch(FetchDescriptor<Entry>())

        #expect(report.categoriesMerged == 1)
        #expect(report.entriesMerged == 0)
        #expect(report.badgeAwardsMerged == 0)
        #expect(categories.count == 1)
        #expect(entries.count == 1)
        #expect(entries[0].category?.id == categories[0].id)
    }

    @Test
    @MainActor
    func syncConflictResolverDeduplicatesEntriesAndBadges() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let category = Category(
            title: "Reading",
            multiplier: 1.0,
            type: .goodHabit,
            dailyGoalMinutes: 30
        )
        modelContext.insert(category)

        let sharedTimestamp = Date.now
        let duplicateEntryA = Entry(
            timestamp: sharedTimestamp,
            durationMinutes: 25,
            amountUSD: Decimal(string: "7.50") ?? .zeroValue,
            category: category,
            note: "manual sync duplicate",
            isManual: true
        )
        let duplicateEntryB = Entry(
            timestamp: sharedTimestamp,
            durationMinutes: 25,
            amountUSD: Decimal(string: "7.50") ?? .zeroValue,
            category: category,
            note: "manual sync duplicate",
            isManual: true
        )
        let uniqueEntry = Entry(
            timestamp: sharedTimestamp.addingTimeInterval(60),
            durationMinutes: 10,
            amountUSD: Decimal(string: "3.00") ?? .zeroValue,
            category: category,
            note: "unique",
            isManual: false
        )

        modelContext.insert(duplicateEntryA)
        modelContext.insert(duplicateEntryB)
        modelContext.insert(uniqueEntry)

        let duplicateAwardA = BadgeAward(awardKey: "streak:reading:3:2026-02-11", dateAwarded: Date.now)
        let duplicateAwardB = BadgeAward(awardKey: "streak:reading:3:2026-02-11", dateAwarded: Date.now.addingTimeInterval(-10))
        let uniqueAward = BadgeAward(awardKey: "streak:reading:7:2026-02-11", dateAwarded: Date.now)

        modelContext.insert(duplicateAwardA)
        modelContext.insert(duplicateAwardB)
        modelContext.insert(uniqueAward)
        try modelContext.save()

        let report = try SyncConflictResolverService.resolveConflictsIfNeeded(in: modelContext)
        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        let awards = try modelContext.fetch(FetchDescriptor<BadgeAward>())

        #expect(report.entriesMerged == 1)
        #expect(report.badgeAwardsMerged == 1)
        #expect(entries.count == 2)
        #expect(awards.count == 2)
    }

    @Test
    @MainActor
    func syncMonitorRestoresPersistedHistoryOnInit() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let importDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let exportDate = Date(timeIntervalSinceReferenceDate: 1_000_300)

        modelContext.insert(
            SyncEventHistory(
                eventIdentifier: UUID().uuidString,
                kindRaw: SyncMonitor.EventRecord.EventKind.importData.rawValue,
                outcomeRaw: "success",
                startedAt: importDate.addingTimeInterval(-5),
                endedAt: importDate,
                detail: nil,
                recordedAt: importDate
            )
        )
        modelContext.insert(
            SyncEventHistory(
                eventIdentifier: UUID().uuidString,
                kindRaw: SyncMonitor.EventRecord.EventKind.exportData.rawValue,
                outcomeRaw: "success",
                startedAt: exportDate.addingTimeInterval(-5),
                endedAt: exportDate,
                detail: nil,
                recordedAt: exportDate
            )
        )
        try modelContext.save()

        let monitor = SyncMonitor(cloudKitEnabled: true, modelContext: modelContext)

        #expect(monitor.lastImportDate == importDate)
        #expect(monitor.lastExportDate == exportDate)
        #expect(monitor.recentEvents.count == 2)

        if case let .upToDate(lastSync) = monitor.status {
            #expect(lastSync == exportDate)
        } else {
            Issue.record("SyncMonitor should report up-to-date after restoring persisted sync history.")
        }
    }

    @Test
    @MainActor
    func onboardingCompletionRespectsStarterToggle() throws {
        let container = try makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let viewModel = OnboardingViewModel()
        viewModel.desiredUSDPerHour = 24
        viewModel.includeStarterCategories = false

        #expect(viewModel.complete(modelContext: modelContext))

        let countWithoutStarters = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(countWithoutStarters == 0)

        viewModel.includeStarterCategories = true
        #expect(viewModel.complete(modelContext: modelContext))

        let countWithStarters = try modelContext.fetchCount(
            FetchDescriptor<Grind_N_Chill.Category>()
        )
        #expect(countWithStarters == 3)
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        return components.date ?? .distantPast
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Grind_N_Chill.Category.self,
            Entry.self,
            BadgeAward.self,
            SyncEventHistory.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
