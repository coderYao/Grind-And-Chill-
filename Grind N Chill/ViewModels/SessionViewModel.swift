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
    var manualCount: Int = 1
    var manualAmountUSD: Double = 5
    var manualNote: String = ""
    var sessionNote: String = ""
    var latestStatus: String?
    var latestError: String?

    func startSession(with timerManager: TimerManager, categories: [Category]) {
        guard
            let selectedCategoryID,
            let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            latestError = "Pick a category before starting."
            return
        }

        guard category.resolvedUnit == .time else {
            latestError = "Live timer is only available for Time categories."
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

        guard category.resolvedUnit == .time else {
            latestError = "Timer sessions can only be saved for Time categories."
            return
        }

        let durationMinutes = max(1, Int((Double(completed.elapsedSeconds) / 60).rounded()))
        let quantity = Decimal(durationMinutes)
        let amount = ledgerService.amountUSD(for: category, quantity: quantity, usdPerHour: usdPerHour)

        let note = sessionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = Entry(
            timestamp: completed.endedAt,
            durationMinutes: durationMinutes,
            amountUSD: amount,
            category: category,
            note: note,
            isManual: false,
            quantity: quantity,
            unit: .time
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

    func pauseSession(with timerManager: TimerManager) {
        guard timerManager.pause() else {
            latestError = "No running session to pause."
            return
        }

        latestStatus = "Session paused."
        latestError = nil
    }

    func resumeSession(with timerManager: TimerManager) {
        guard timerManager.resume() else {
            latestError = "No paused session to resume."
            return
        }

        latestStatus = "Session resumed."
        latestError = nil
    }

    func addManualEntry(
        categories: [Category],
        existingEntries: [Entry],
        modelContext: ModelContext,
        usdPerHour: Decimal
    ) {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            latestError = "Pick a category before logging an entry."
            return
        }

        let durationMinutes: Int
        let quantity: Decimal

        switch category.resolvedUnit {
        case .time:
            guard manualMinutes > 0, manualMinutes <= 600 else {
                latestError = "Manual minutes must be between 1 and 600."
                return
            }
            durationMinutes = manualMinutes
            quantity = Decimal(manualMinutes)
        case .count:
            guard manualCount > 0, manualCount <= 500 else {
                latestError = "Count must be between 1 and 500."
                return
            }
            durationMinutes = 0
            quantity = Decimal(manualCount)
        case .money:
            guard manualAmountUSD > 0 else {
                latestError = "Amount must be greater than zero."
                return
            }
            durationMinutes = 0
            quantity = decimal(from: manualAmountUSD)
        }

        let amount = ledgerService.amountUSD(for: category, quantity: quantity, usdPerHour: usdPerHour)

        let note = manualNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = Entry(
            timestamp: .now,
            durationMinutes: durationMinutes,
            amountUSD: amount,
            category: category,
            note: note,
            isManual: true,
            quantity: quantity,
            unit: category.resolvedUnit
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

    func incrementManualCount(by value: Int) {
        guard value > 0 else { return }
        manualCount = max(1, manualCount + value)
    }

    func incrementManualAmount(by value: Decimal) {
        guard value > .zeroValue else { return }
        let current = Decimal(string: String(manualAmountUSD)) ?? Decimal(manualAmountUSD)
        let updated = (current + value).rounded(scale: 2)
        manualAmountUSD = NSDecimalNumber(decimal: updated).doubleValue
    }

    func liveAmountUSD(
        for category: Category?,
        elapsedSeconds: Int,
        usdPerHour: Decimal
    ) -> Decimal? {
        guard let category, category.resolvedUnit == .time else { return nil }
        let clampedSeconds = max(0, elapsedSeconds)
        let minutes = Decimal(clampedSeconds) / Decimal(60)
        return ledgerService.amountUSD(
            for: category,
            quantity: minutes,
            usdPerHour: usdPerHour
        )
    }

    private func decimal(from value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }
}
