import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var title: String = ""
    var multiplier: Double = 1.0
    var type: CategoryType? = CategoryType.goodHabit
    var unit: CategoryUnit? = CategoryUnit.time
    var timeConversionMode: TimeConversionMode? = TimeConversionMode.multiplier
    var hourlyRateUSD: Double?
    var usdPerCount: Double?
    var dailyGoalMinutes: Int = 0
    var symbolName: String?
    @Relationship(deleteRule: .cascade) var entries: [Entry]

    init(
        id: UUID = UUID(),
        title: String,
        multiplier: Double,
        type: CategoryType,
        dailyGoalMinutes: Int,
        symbolName: String? = nil,
        unit: CategoryUnit = .time,
        timeConversionMode: TimeConversionMode = .multiplier,
        hourlyRateUSD: Double? = nil,
        usdPerCount: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.multiplier = multiplier
        self.type = type
        self.unit = unit
        self.timeConversionMode = unit == .time ? timeConversionMode : nil
        self.hourlyRateUSD = hourlyRateUSD
        self.usdPerCount = usdPerCount
        self.dailyGoalMinutes = dailyGoalMinutes
        self.symbolName = symbolName
        self.entries = []
    }

    var resolvedType: CategoryType {
        type ?? .goodHabit
    }

    var resolvedUnit: CategoryUnit {
        unit ?? .time
    }

    var resolvedTimeConversionMode: TimeConversionMode {
        timeConversionMode ?? .multiplier
    }

    var resolvedHourlyRateUSD: Decimal? {
        guard let hourlyRateUSD, hourlyRateUSD > 0 else { return nil }
        return Decimal(string: String(hourlyRateUSD)) ?? Decimal(hourlyRateUSD)
    }

    var resolvedUSDPerCount: Decimal {
        guard let usdPerCount, usdPerCount > 0 else { return Decimal(1) }
        return Decimal(string: String(usdPerCount)) ?? Decimal(usdPerCount)
    }

    var resolvedSymbolName: String {
        symbolName ?? resolvedType.symbolName
    }
}
