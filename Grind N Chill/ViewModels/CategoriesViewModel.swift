import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CategoriesViewModel {
    enum EditorMode {
        case create
        case edit
    }

    var isPresentingEditorSheet = false
    var editorMode: EditorMode = .create
    private var editingCategoryID: UUID?

    var title: String = ""
    var multiplier: Double = 1.0
    var type: CategoryType = .goodHabit {
        didSet {
            symbolName = CategorySymbolCatalog.normalizedSymbol(symbolName, for: type)
            if iconColor == CategoryIconColor.defaultColor(for: oldValue) {
                iconColor = CategoryIconColor.defaultColor(for: type)
            }
        }
    }
    var unit: CategoryUnit = .time
    var timeConversionMode: TimeConversionMode = .multiplier
    var hourlyRateUSD: Double = 18
    var usdPerCount: Double = 1
    var symbolName: String = CategorySymbolCatalog.defaultSymbol(for: .goodHabit)
    var iconColor: CategoryIconColor = .green
    var dailyGoalMinutes: Int = 30
    var streakEnabled: Bool = true
    var badgeEnabled: Bool = true
    var badgeMilestonesInput: String = "3, 7, 30"
    var streakBonusEnabled: Bool = false
    var streakBonusAmountsUSD: [Int: Double] = [:]

    var latestError: String?
    var latestStatus: String?
    private let defaultStreakBonusAmountUSD = 5.0

    var editorSheetTitle: String {
        switch editorMode {
        case .create:
            return "New Category"
        case .edit:
            return "Edit Category"
        }
    }

    func beginCreating() {
        resetForm()
        editorMode = .create
        editingCategoryID = nil
        isPresentingEditorSheet = true
        latestError = nil
        latestStatus = nil
    }

    func beginEditing(_ category: Category) {
        editorMode = .edit
        editingCategoryID = category.id
        title = category.title
        multiplier = category.multiplier
        type = category.resolvedType
        unit = category.resolvedUnit
        timeConversionMode = category.resolvedTimeConversionMode
        hourlyRateUSD = category.hourlyRateUSD ?? 18
        usdPerCount = category.usdPerCount ?? 1
        symbolName = CategorySymbolCatalog.normalizedSymbol(category.resolvedSymbolName, for: category.resolvedType)
        iconColor = category.resolvedIconColor
        dailyGoalMinutes = category.dailyGoalMinutes
        streakEnabled = category.resolvedStreakEnabled
        badgeEnabled = category.resolvedBadgeEnabled
        let milestones = category.resolvedBadgeMilestones()
        badgeMilestonesInput = milestones
            .map(String.init)
            .joined(separator: ", ")
        streakBonusEnabled = category.resolvedStreakBonusEnabled
        let resolvedBonusSchedule = category.resolvedStreakBonusAmounts(defaultMilestones: milestones)
        streakBonusAmountsUSD = milestones.reduce(into: [:]) { partialResult, milestone in
            let amount = resolvedBonusSchedule[milestone] ?? Decimal(defaultStreakBonusAmountUSD)
            partialResult[milestone] = NSDecimalNumber(decimal: amount.rounded(scale: 2)).doubleValue
        }
        latestError = nil
        latestStatus = nil
        isPresentingEditorSheet = true
    }

    @discardableResult
    func saveCategory(in modelContext: ModelContext, existingCategories: [Category]) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedTitle.isEmpty == false else {
            latestError = "Category title is required."
            return false
        }

        guard dailyGoalMinutes >= 0 else {
            latestError = "Daily goal cannot be negative."
            return false
        }

        if streakEnabled == false {
            badgeEnabled = false
            streakBonusEnabled = false
        }

        let normalizedMilestones: String?
        if streakEnabled, (badgeEnabled || streakBonusEnabled) {
            guard let milestones = parsedBadgeMilestones(from: badgeMilestonesInput) else {
                latestError = "Milestones must be comma-separated positive days (example: 3, 7, 30)."
                return false
            }
            normalizedMilestones = milestones.map(String.init).joined(separator: ",")
        } else {
            normalizedMilestones = nil
        }

        let normalizedBonusSchedule: String?
        let representativeBonusAmount: Double?
        if streakEnabled && streakBonusEnabled {
            guard let milestones = parsedBadgeMilestones(from: badgeMilestonesInput) else {
                latestError = "Milestones must be comma-separated positive days (example: 3, 7, 30)."
                return false
            }

            var bonusSchedule: [Int: Decimal] = [:]
            for milestone in milestones {
                let rawAmount = streakBonusAmountsUSD[milestone] ?? defaultStreakBonusAmountUSD
                guard rawAmount > 0 else {
                    latestError = "Each streak bonus amount must be greater than zero."
                    return false
                }

                let decimalAmount = (Decimal(string: String(rawAmount)) ?? Decimal(rawAmount)).rounded(scale: 2)
                guard decimalAmount > .zeroValue else {
                    latestError = "Each streak bonus amount must be greater than zero."
                    return false
                }
                bonusSchedule[milestone] = decimalAmount
            }

            normalizedBonusSchedule = Category.encodeStreakBonusSchedule(bonusSchedule)
            representativeBonusAmount = milestones.first.flatMap { streakBonusAmountsUSD[$0] } ?? defaultStreakBonusAmountUSD
            streakBonusAmountsUSD = milestones.reduce(into: [:]) { partialResult, milestone in
                partialResult[milestone] = streakBonusAmountsUSD[milestone] ?? defaultStreakBonusAmountUSD
            }
        } else {
            normalizedBonusSchedule = nil
            representativeBonusAmount = nil
        }

        switch unit {
        case .time:
            switch timeConversionMode {
            case .multiplier:
                guard multiplier > 0 else {
                    latestError = "Multiplier must be greater than zero."
                    return false
                }
            case .hourlyRate:
                guard hourlyRateUSD > 0 else {
                    latestError = "Hourly rate must be greater than zero."
                    return false
                }
            }
        case .count:
            guard usdPerCount > 0 else {
                latestError = "Value per count must be greater than zero."
                return false
            }
        case .money:
            break
        }

        let normalizedSymbol = CategorySymbolCatalog.normalizedSymbol(symbolName, for: type)

        if let editingCategoryID,
           let category = existingCategories.first(where: { $0.id == editingCategoryID }) {
            category.title = normalizedTitle
            category.multiplier = max(1, multiplier)
            category.type = type
            category.unit = unit
            category.timeConversionMode = unit == .time ? timeConversionMode : nil
            category.hourlyRateUSD = (unit == .time && timeConversionMode == .hourlyRate) ? hourlyRateUSD : nil
            category.usdPerCount = unit == .count ? usdPerCount : nil
            category.dailyGoalMinutes = dailyGoalMinutes
            category.streakEnabled = streakEnabled
            category.badgeEnabled = streakEnabled ? badgeEnabled : false
            category.badgeMilestones = normalizedMilestones
            category.streakBonusEnabled = streakEnabled ? streakBonusEnabled : false
            category.streakBonusAmountUSD = representativeBonusAmount
            category.streakBonusSchedule = normalizedBonusSchedule
            category.symbolName = normalizedSymbol
            category.iconColor = iconColor
        } else {
            let category = Category(
                title: normalizedTitle,
                multiplier: max(1, multiplier),
                type: type,
                dailyGoalMinutes: dailyGoalMinutes,
                symbolName: normalizedSymbol,
                iconColor: iconColor,
                unit: unit,
                timeConversionMode: timeConversionMode,
                hourlyRateUSD: (unit == .time && timeConversionMode == .hourlyRate) ? hourlyRateUSD : nil,
                usdPerCount: unit == .count ? usdPerCount : nil,
                streakEnabled: streakEnabled,
                badgeEnabled: streakEnabled ? badgeEnabled : false,
                badgeMilestones: normalizedMilestones,
                streakBonusEnabled: streakEnabled ? streakBonusEnabled : false,
                streakBonusAmountUSD: representativeBonusAmount,
                streakBonusSchedule: normalizedBonusSchedule
            )
            modelContext.insert(category)
        }

        do {
            try modelContext.save()
            editingCategoryID = nil
            resetForm()
            latestError = nil
            latestStatus = "Category saved."
            isPresentingEditorSheet = false
            return true
        } catch {
            latestError = "Could not save category: \(error.localizedDescription)"
            latestStatus = nil
            return false
        }
    }

    func cancelCategoryEditing() {
        editingCategoryID = nil
        resetForm()
        latestError = nil
        latestStatus = nil
        isPresentingEditorSheet = false
    }

    func deleteCategories(
        at offsets: IndexSet,
        from categories: [Category],
        modelContext: ModelContext,
        activeCategoryID: UUID?
    ) {
        if let activeCategoryID,
           let activeCategory = offsets
            .map({ categories[$0] })
            .first(where: { $0.id == activeCategoryID }) {
            latestError = "Stop the active session before deleting \(activeCategory.title)."
            return
        }

        for index in offsets {
            modelContext.delete(categories[index])
        }

        do {
            try modelContext.save()
            latestError = nil
            latestStatus = "Category deleted."
        } catch {
            latestError = "Could not delete category: \(error.localizedDescription)"
            latestStatus = nil
        }
    }

    func seedDefaultsIfNeeded(in modelContext: ModelContext, existingCategories: [Category]) {
        guard existingCategories.isEmpty else { return }

        do {
            try CategorySeeder.seedIfNeeded(in: modelContext)
            latestStatus = "Starter categories created."
        } catch {
            latestError = "Could not seed defaults: \(error.localizedDescription)"
            latestStatus = nil
        }
    }

    func resetForm() {
        title = ""
        multiplier = 1.0
        type = .goodHabit
        unit = .time
        timeConversionMode = .multiplier
        hourlyRateUSD = 18
        usdPerCount = 1
        symbolName = CategorySymbolCatalog.defaultSymbol(for: .goodHabit)
        iconColor = CategoryIconColor.defaultColor(for: type)
        dailyGoalMinutes = 30
        streakEnabled = true
        badgeEnabled = true
        badgeMilestonesInput = "3, 7, 30"
        streakBonusEnabled = false
        streakBonusAmountsUSD = [:]
    }

    func symbolOptions() -> [String] {
        CategorySymbolCatalog.symbols(for: type)
    }

    func conversionSummary(for category: Category) -> String {
        switch category.resolvedUnit {
        case .time:
            switch category.resolvedTimeConversionMode {
            case .multiplier:
                return "Time • x\(category.multiplier.formatted(.number.precision(.fractionLength(2)))) multiplier"
            case .hourlyRate:
                if let rate = category.resolvedHourlyRateUSD {
                    return "Time • \(rate.formatted(.currency(code: "USD")))/hr"
                }
                return "Time • global hourly rate"
            }
        case .count:
            return "Count • \(category.resolvedUSDPerCount.formatted(.currency(code: "USD"))) each"
        case .money:
            return "Money • direct USD"
        }
    }

    func goalSummary(for category: Category) -> String {
        guard category.resolvedStreakEnabled else {
            return "Streak off"
        }

        let thresholdText: String
        switch category.resolvedUnit {
        case .time:
            thresholdText = "\(category.dailyGoalMinutes)m"
        case .count:
            thresholdText = "\(category.dailyGoalMinutes) count"
        case .money:
            thresholdText = Decimal(category.dailyGoalMinutes).formatted(.currency(code: "USD"))
        }

        switch category.resolvedType {
        case .goodHabit:
            return "Goal \(thresholdText)"
        case .quitHabit:
            return "Target < \(thresholdText)"
        }
    }

    func dailyGoalLabel() -> String {
        guard streakEnabled else {
            return "Streak Tracking Disabled"
        }

        let thresholdText: String
        switch unit {
        case .time:
            thresholdText = "\(dailyGoalMinutes)m"
        case .count:
            thresholdText = "\(dailyGoalMinutes) count"
        case .money:
            thresholdText = Decimal(dailyGoalMinutes).formatted(.currency(code: "USD"))
        }

        switch type {
        case .goodHabit:
            return "Daily Goal: \(thresholdText)"
        case .quitHabit:
            return "Daily Target: < \(thresholdText)"
        }
    }

    func dailyGoalRange() -> ClosedRange<Int> {
        switch unit {
        case .time:
            return 0 ... 600
        case .count:
            return 0 ... 500
        case .money:
            return 0 ... 10_000
        }
    }

    func rewardMilestonesPreview() -> [Int] {
        parsedBadgeMilestones(from: badgeMilestonesInput) ?? []
    }

    func streakBonusAmount(for milestone: Int) -> Double {
        let configuredAmount = streakBonusAmountsUSD[milestone]
        guard let configuredAmount, configuredAmount > 0 else {
            return defaultStreakBonusAmountUSD
        }
        return configuredAmount
    }

    func setStreakBonusAmount(_ amount: Double, for milestone: Int) {
        streakBonusAmountsUSD[milestone] = amount
    }

    private func parsedBadgeMilestones(from raw: String) -> [Int]? {
        let values = raw
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0) }
            .filter { $0 > 0 }

        let normalized = Array(Set(values)).sorted()
        return normalized.isEmpty ? nil : normalized
    }
}
