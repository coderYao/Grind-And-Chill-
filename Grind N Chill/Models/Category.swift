import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID = UUID()
    var title: String = ""
    var multiplier: Double = 1.0
    var type: CategoryType? = CategoryType.goodHabit
    var unit: CategoryUnit? = CategoryUnit.time
    var timeConversionMode: TimeConversionMode? = TimeConversionMode.multiplier
    var hourlyRateUSD: Double?
    var usdPerCount: Double?
    var dailyGoalMinutes: Int = 0
    var streakEnabled: Bool?
    var badgeEnabled: Bool?
    var badgeMilestones: String?
    var streakBonusEnabled: Bool?
    var streakBonusAmountUSD: Double?
    var streakBonusSchedule: String?
    var symbolName: String?
    var iconColor: CategoryIconColor?
    @Relationship(deleteRule: .cascade, inverse: \Entry.category) var entries: [Entry]?

    init(
        id: UUID = UUID(),
        title: String,
        multiplier: Double,
        type: CategoryType,
        dailyGoalMinutes: Int,
        symbolName: String? = nil,
        iconColor: CategoryIconColor? = nil,
        unit: CategoryUnit = .time,
        timeConversionMode: TimeConversionMode = .multiplier,
        hourlyRateUSD: Double? = nil,
        usdPerCount: Double? = nil,
        streakEnabled: Bool = true,
        badgeEnabled: Bool = true,
        badgeMilestones: String? = nil,
        streakBonusEnabled: Bool = false,
        streakBonusAmountUSD: Double? = nil,
        streakBonusSchedule: String? = nil
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
        self.streakEnabled = streakEnabled
        self.badgeEnabled = badgeEnabled
        self.badgeMilestones = badgeMilestones
        self.streakBonusEnabled = streakBonusEnabled
        self.streakBonusAmountUSD = streakBonusAmountUSD
        self.streakBonusSchedule = streakBonusSchedule
        self.symbolName = symbolName
        self.iconColor = iconColor
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

    var resolvedIconColor: CategoryIconColor {
        iconColor ?? CategoryIconColor.defaultColor(for: resolvedType)
    }

    var resolvedStreakEnabled: Bool {
        streakEnabled ?? true
    }

    var resolvedBadgeEnabled: Bool {
        badgeEnabled ?? true
    }

    var resolvedStreakBonusEnabled: Bool {
        streakBonusEnabled ?? false
    }

    var resolvedStreakBonusAmountUSD: Decimal? {
        guard let streakBonusAmountUSD, streakBonusAmountUSD > 0 else { return nil }
        return Decimal(string: String(streakBonusAmountUSD)) ?? Decimal(streakBonusAmountUSD)
    }

    func resolvedStreakBonusAmounts(defaultMilestones: [Int]? = nil) -> [Int: Decimal] {
        let parsedSchedule = Category.parseStreakBonusSchedule(streakBonusSchedule)
        if parsedSchedule.isEmpty == false {
            return parsedSchedule
        }

        guard let fallbackAmount = resolvedStreakBonusAmountUSD else {
            return [:]
        }

        let milestones = defaultMilestones ?? resolvedBadgeMilestones()
        var fallbackSchedule: [Int: Decimal] = [:]
        for milestone in milestones {
            fallbackSchedule[milestone] = fallbackAmount.rounded(scale: 2)
        }
        return fallbackSchedule
    }

    func resolvedBadgeMilestones(defaults: [Int] = [3, 7, 30]) -> [Int] {
        let source = badgeMilestones?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard source.isEmpty == false else { return defaults }

        let values = source
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0) }
            .filter { $0 > 0 }

        let normalized = Array(Set(values)).sorted()
        return normalized.isEmpty ? defaults : normalized
    }

    static func parseStreakBonusSchedule(_ raw: String?) -> [Int: Decimal] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return [:]
        }

        let locale = Locale(identifier: "en_US_POSIX")
        var schedule: [Int: Decimal] = [:]

        for token in raw.split(separator: ",") {
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let milestoneText = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let amountText = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let milestone = Int(milestoneText), milestone > 0 else { continue }
            guard let amount = Decimal(string: amountText, locale: locale) ?? Decimal(string: amountText),
                  amount > .zeroValue else {
                continue
            }

            schedule[milestone] = amount.rounded(scale: 2)
        }

        return schedule
    }

    static func encodeStreakBonusSchedule(_ schedule: [Int: Decimal]) -> String? {
        guard schedule.isEmpty == false else { return nil }

        let normalizedParts = schedule
            .filter { $0.key > 0 && $0.value > .zeroValue }
            .sorted { $0.key < $1.key }
            .map { milestone, amount in
                let amountString = NSDecimalNumber(decimal: amount.rounded(scale: 2)).stringValue
                return "\(milestone):\(amountString)"
            }

        guard normalizedParts.isEmpty == false else { return nil }
        return normalizedParts.joined(separator: ",")
    }
}
