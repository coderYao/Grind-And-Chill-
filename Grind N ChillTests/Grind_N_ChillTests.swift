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
        viewModel.dailyGoalMinutes = 75

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

        viewModel.beginEditing(savedCategory)
        viewModel.title = "Writing Sprint"
        viewModel.multiplier = 1.4
        viewModel.dailyGoalMinutes = 90

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
