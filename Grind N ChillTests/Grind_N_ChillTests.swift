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
            BadgeAward.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
