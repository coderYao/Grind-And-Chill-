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

        guard multiplier > 0 else {
            latestError = "Multiplier must be greater than zero."
            return false
        }

        guard dailyGoalMinutes >= 0 else {
            latestError = "Daily goal cannot be negative."
            return false
        }

        let normalizedSymbol = CategorySymbolCatalog.normalizedSymbol(symbolName, for: type)

        if let editingCategoryID,
           let category = existingCategories.first(where: { $0.id == editingCategoryID }) {
            category.title = normalizedTitle
            category.multiplier = multiplier
            category.type = type
            category.dailyGoalMinutes = dailyGoalMinutes
            category.symbolName = normalizedSymbol
        } else {
            let category = Category(
                title: normalizedTitle,
                multiplier: multiplier,
                type: type,
                dailyGoalMinutes: dailyGoalMinutes,
                symbolName: normalizedSymbol
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
        symbolName = CategorySymbolCatalog.defaultSymbol(for: .goodHabit)
        dailyGoalMinutes = 30
    }

    func symbolOptions() -> [String] {
        CategorySymbolCatalog.symbols(for: type)
    }
}
