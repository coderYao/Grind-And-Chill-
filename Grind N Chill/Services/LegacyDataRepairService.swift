import Foundation
import SwiftData

enum LegacyDataRepairService {
    @MainActor
    static func repairCategoriesIfNeeded(in modelContext: ModelContext) throws -> Int {
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        var repairedCount = 0

        for category in categories {
            var repaired = false

            if category.type == nil {
                category.type = .goodHabit
                repaired = true
            }

            if category.unit == nil {
                category.unit = .time
                repaired = true
            }

            if category.timeConversionMode == nil, category.resolvedUnit == .time {
                category.timeConversionMode = .multiplier
                repaired = true
            }

            if category.dailyGoalMinutes < 0 {
                category.dailyGoalMinutes = 0
                repaired = true
            }

            if category.streakEnabled == nil {
                category.streakEnabled = true
                repaired = true
            }

            if category.badgeEnabled == nil {
                category.badgeEnabled = true
                repaired = true
            }

            if category.streakBonusEnabled == nil {
                category.streakBonusEnabled = false
                repaired = true
            }

            if category.resolvedStreakEnabled == false, category.resolvedBadgeEnabled {
                category.badgeEnabled = false
                repaired = true
            }

            if category.resolvedStreakEnabled == false, category.resolvedStreakBonusEnabled {
                category.streakBonusEnabled = false
                repaired = true
            }

            let normalizedMilestones = category
                .resolvedBadgeMilestones()
                .map(String.init)
                .joined(separator: ",")
            if let stored = category.badgeMilestones?.trimmingCharacters(in: .whitespacesAndNewlines),
               stored.isEmpty == false,
               stored != normalizedMilestones {
                category.badgeMilestones = normalizedMilestones
                repaired = true
            }

            if let bonusAmount = category.streakBonusAmountUSD, bonusAmount <= 0 {
                category.streakBonusAmountUSD = nil
                repaired = true
            }

            let parsedBonusSchedule = Category.parseStreakBonusSchedule(category.streakBonusSchedule)
            let normalizedBonusSchedule = Category.encodeStreakBonusSchedule(parsedBonusSchedule)
            if category.streakBonusSchedule != normalizedBonusSchedule {
                category.streakBonusSchedule = normalizedBonusSchedule
                repaired = true
            }

            if category.streakBonusSchedule == nil, let legacyBonusAmount = category.streakBonusAmountUSD, legacyBonusAmount > 0 {
                let milestones = category.resolvedBadgeMilestones()
                let legacyBonus = (Decimal(string: String(legacyBonusAmount)) ?? Decimal(legacyBonusAmount)).rounded(scale: 2)
                let migratedSchedule = milestones.reduce(into: [Int: Decimal]()) { partialResult, milestone in
                    partialResult[milestone] = legacyBonus
                }
                category.streakBonusSchedule = Category.encodeStreakBonusSchedule(migratedSchedule)
                repaired = true
            }

            if category.resolvedStreakBonusEnabled {
                let resolvedSchedule = category.resolvedStreakBonusAmounts(defaultMilestones: category.resolvedBadgeMilestones())
                if resolvedSchedule.isEmpty {
                    category.streakBonusEnabled = false
                    repaired = true
                }
            }

            if category.multiplier <= 0 {
                category.multiplier = 1
                repaired = true
            }

            if let hourlyRateUSD = category.hourlyRateUSD, hourlyRateUSD <= 0 {
                category.hourlyRateUSD = nil
                repaired = true
            }

            if category.resolvedUnit == .count, (category.usdPerCount == nil || category.usdPerCount ?? 0 <= 0) {
                category.usdPerCount = 1
                repaired = true
            }

            if category.resolvedUnit != .time, category.timeConversionMode != nil {
                category.timeConversionMode = nil
                repaired = true
            }

            if category.resolvedUnit != .time, category.hourlyRateUSD != nil {
                category.hourlyRateUSD = nil
                repaired = true
            }

            if category.resolvedUnit != .count, category.usdPerCount != nil {
                category.usdPerCount = nil
                repaired = true
            }

            let normalizedSymbol = CategorySymbolCatalog.normalizedSymbol(
                category.resolvedSymbolName,
                for: category.resolvedType
            )
            if category.symbolName != normalizedSymbol {
                category.symbolName = normalizedSymbol
                repaired = true
            }

            if repaired {
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            try modelContext.save()
        }

        return repairedCount
    }
}
