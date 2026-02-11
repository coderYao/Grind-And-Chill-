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
