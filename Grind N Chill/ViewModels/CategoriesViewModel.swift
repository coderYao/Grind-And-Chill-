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
        }
    }
    var unit: CategoryUnit = .time
    var timeConversionMode: TimeConversionMode = .multiplier
    var hourlyRateUSD: Double = 18
    var usdPerCount: Double = 1
    var symbolName: String = CategorySymbolCatalog.defaultSymbol(for: .goodHabit)
    var dailyGoalMinutes: Int = 30

    var latestError: String?
    var latestStatus: String?

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
        dailyGoalMinutes = category.dailyGoalMinutes
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
            category.symbolName = normalizedSymbol
        } else {
            let category = Category(
                title: normalizedTitle,
                multiplier: max(1, multiplier),
                type: type,
                dailyGoalMinutes: dailyGoalMinutes,
                symbolName: normalizedSymbol,
                unit: unit,
                timeConversionMode: timeConversionMode,
                hourlyRateUSD: (unit == .time && timeConversionMode == .hourlyRate) ? hourlyRateUSD : nil,
                usdPerCount: unit == .count ? usdPerCount : nil
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
        dailyGoalMinutes = 30
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
        switch category.resolvedUnit {
        case .time:
            return "Goal \(category.dailyGoalMinutes)m"
        case .count:
            return "Goal \(category.dailyGoalMinutes) count"
        case .money:
            return "Goal \(Decimal(category.dailyGoalMinutes).formatted(.currency(code: "USD")))"
        }
    }

    func dailyGoalLabel() -> String {
        switch unit {
        case .time:
            return "Daily Goal: \(dailyGoalMinutes)m"
        case .count:
            return "Daily Goal: \(dailyGoalMinutes) count"
        case .money:
            return "Daily Goal: \(Decimal(dailyGoalMinutes).formatted(.currency(code: "USD")))"
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
}
