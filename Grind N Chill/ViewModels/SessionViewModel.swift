import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SessionViewModel {
    private let ledgerService = LedgerService()
    private let badgeService = BadgeService()

    var selectedCategoryID: UUID?
    var manualMinutes: Int = 30
    var manualNote: String = ""
    var sessionNote: String = ""
    var latestStatus: String?
    var latestError: String?

    func startSession(with timerManager: TimerManager) {
        guard let selectedCategoryID else {
            latestError = "Pick a category before starting."
            return
        }

        latestError = nil
        latestStatus = nil
        timerManager.start(categoryID: selectedCategoryID)
    }

    func stopSession(
        with timerManager: TimerManager,
        categories: [Category],
        existingEntries: [Entry],
        modelContext: ModelContext,
        usdPerHour: Decimal
    ) {
        guard let completed = timerManager.stop() else {
            latestError = "No running session to stop."
            return
        }

        guard let category = categories.first(where: { $0.id == completed.categoryID }) else {
            latestError = "Could not find the selected category."
            return
        }

        let durationMinutes = max(1, Int((Double(completed.elapsedSeconds) / 60).rounded()))
        let amount = ledgerService.earnedUSD(
            minutes: durationMinutes,
            usdPerHour: usdPerHour,
            categoryMultiplier: category.multiplier,
            categoryType: category.resolvedType
        )

        let note = sessionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = Entry(
            timestamp: completed.endedAt,
            durationMinutes: durationMinutes,
            amountUSD: amount,
            category: category,
            note: note,
            isManual: false
        )

        modelContext.insert(entry)

        do {
            var entriesForBadges = existingEntries
            entriesForBadges.insert(entry, at: 0)
            _ = try badgeService.awardBadgesIfNeeded(
                for: category,
                entries: entriesForBadges,
                modelContext: modelContext,
                now: completed.endedAt
            )
            try modelContext.save()
            sessionNote = ""
            latestStatus = "Session saved."
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Failed to save session: \(error.localizedDescription)"
        }
    }

    func addManualEntry(
        categories: [Category],
        existingEntries: [Entry],
        modelContext: ModelContext,
        usdPerHour: Decimal
    ) {
        guard manualMinutes > 0 else {
            latestError = "Manual minutes must be greater than zero."
            return
        }

        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            latestError = "Pick a category before logging an entry."
            return
        }

        let amount = ledgerService.earnedUSD(
            minutes: manualMinutes,
            usdPerHour: usdPerHour,
            categoryMultiplier: category.multiplier,
            categoryType: category.resolvedType
        )

        let note = manualNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = Entry(
            timestamp: .now,
            durationMinutes: manualMinutes,
            amountUSD: amount,
            category: category,
            note: note,
            isManual: true
        )

        modelContext.insert(entry)

        do {
            var entriesForBadges = existingEntries
            entriesForBadges.insert(entry, at: 0)
            _ = try badgeService.awardBadgesIfNeeded(
                for: category,
                entries: entriesForBadges,
                modelContext: modelContext
            )
            try modelContext.save()
            manualNote = ""
            latestStatus = "Manual entry saved."
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Failed to save entry: \(error.localizedDescription)"
        }
    }

    func ensureCategorySelection(from categories: [Category], runningCategoryID: UUID?) {
        if let runningCategoryID {
            selectedCategoryID = runningCategoryID
            return
        }

        guard let currentID = selectedCategoryID else {
            selectedCategoryID = categories.first?.id
            return
        }

        if categories.contains(where: { $0.id == currentID }) == false {
            selectedCategoryID = categories.first?.id
        }
    }

    func categoryTitle(for categories: [Category], id: UUID?) -> String {
        guard
            let id,
            let category = categories.first(where: { $0.id == id })
        else {
            return "No category"
        }

        return category.title
    }
}
