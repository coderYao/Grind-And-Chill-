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

            if StreakCadence(rawValue: category.streakCadenceRawValue ?? "") == nil {
                category.streakCadenceRawValue = StreakCadence.daily.rawValue
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

enum SyncConflictResolverService {
    struct MergeReport: Equatable {
        var categoriesMerged: Int = 0
        var entriesMerged: Int = 0
        var badgeAwardsMerged: Int = 0

        var totalResolved: Int {
            categoriesMerged + entriesMerged + badgeAwardsMerged
        }
    }

    @MainActor
    static func resolveConflictsIfNeeded(in modelContext: ModelContext) throws -> MergeReport {
        var report = MergeReport()

        report.badgeAwardsMerged = try mergeDuplicateBadgeAwards(in: modelContext)
        report.categoriesMerged = try mergeDuplicateCategories(in: modelContext)
        report.entriesMerged = try mergeDuplicateEntries(in: modelContext)

        if report.totalResolved > 0 {
            try modelContext.save()
        }

        return report
    }

    @MainActor
    private static func mergeDuplicateBadgeAwards(in modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<BadgeAward>(
            sortBy: [SortDescriptor(\.dateAwarded, order: .reverse)]
        )
        let awards = try modelContext.fetch(descriptor)

        var resolvedCount = 0
        var seenAwardKeys = Set<String>()

        for award in awards {
            if seenAwardKeys.contains(award.awardKey) {
                modelContext.delete(award)
                resolvedCount += 1
            } else {
                seenAwardKeys.insert(award.awardKey)
            }
        }

        return resolvedCount
    }

    @MainActor
    private static func mergeDuplicateCategories(in modelContext: ModelContext) throws -> Int {
        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        let grouped = Dictionary(grouping: categories, by: categoryMergeKey(for:))

        var resolvedCount = 0

        for (_, group) in grouped where group.count > 1 {
            guard let primary = preferredCategory(in: group) else { continue }

            for duplicate in group where duplicate.id != primary.id {
                for entry in duplicate.entries ?? [] {
                    entry.category = primary
                }

                mergeCategoryMetadata(into: primary, from: duplicate)
                modelContext.delete(duplicate)
                resolvedCount += 1
            }
        }

        return resolvedCount
    }

    @MainActor
    private static func mergeDuplicateEntries(in modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Entry>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id)
            ]
        )
        let entries = try modelContext.fetch(descriptor)

        var resolvedCount = 0
        var seenEntrySignatures = Set<String>()

        for entry in entries {
            let signature = entryMergeSignature(for: entry)
            if seenEntrySignatures.contains(signature) {
                modelContext.delete(entry)
                resolvedCount += 1
            } else {
                seenEntrySignatures.insert(signature)
            }
        }

        return resolvedCount
    }

    private static func categoryMergeKey(for category: Category) -> String {
        let normalizedTitle = category
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalizedTitle.isEmpty == false else {
            return "id:\(category.id.uuidString)"
        }

        return [
            normalizedTitle,
            category.resolvedType.rawValue,
            category.resolvedUnit.rawValue,
            category.resolvedStreakCadence.rawValue
        ].joined(separator: "|")
    }

    private static func preferredCategory(in categories: [Category]) -> Category? {
        categories.max { lhs, rhs in
            let lhsScore = categoryCompletenessScore(lhs)
            let rhsScore = categoryCompletenessScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    private static func categoryCompletenessScore(_ category: Category) -> Int {
        var score = 0
        score += (category.entries?.count ?? 0) * 10
        score += category.symbolName == nil ? 0 : 2
        score += category.iconColor == nil ? 0 : 2
        score += category.hourlyRateUSD == nil ? 0 : 1
        score += category.usdPerCount == nil ? 0 : 1
        score += category.streakCadenceRawValue == nil ? 0 : 1
        score += category.badgeMilestones?.isEmpty == false ? 1 : 0
        score += category.streakBonusSchedule?.isEmpty == false ? 1 : 0
        return score
    }

    private static func mergeCategoryMetadata(into primary: Category, from duplicate: Category) {
        if primary.symbolName == nil, let symbolName = duplicate.symbolName {
            primary.symbolName = symbolName
        }

        if primary.iconColor == nil, let iconColor = duplicate.iconColor {
            primary.iconColor = iconColor
        }

        if primary.hourlyRateUSD == nil, let hourlyRateUSD = duplicate.hourlyRateUSD {
            primary.hourlyRateUSD = hourlyRateUSD
        }

        if primary.usdPerCount == nil, let usdPerCount = duplicate.usdPerCount {
            primary.usdPerCount = usdPerCount
        }

        if primary.streakCadenceRawValue == nil, let cadence = duplicate.streakCadenceRawValue {
            primary.streakCadenceRawValue = cadence
        }

        if primary.badgeMilestones == nil, let badgeMilestones = duplicate.badgeMilestones {
            primary.badgeMilestones = badgeMilestones
        }

        if primary.streakBonusSchedule == nil, let streakBonusSchedule = duplicate.streakBonusSchedule {
            primary.streakBonusSchedule = streakBonusSchedule
        }
    }

    private static func entryMergeSignature(for entry: Entry) -> String {
        let categoryID = entry.category?.id.uuidString ?? "none"
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let bonusKey = entry.bonusKey ?? "none"
        let unit = entry.unit?.rawValue ?? "none"
        let quantity = entry.quantity.map { NSDecimalNumber(decimal: $0.rounded(scale: 4)).stringValue } ?? "none"
        let amount = NSDecimalNumber(decimal: entry.amountUSD.rounded(scale: 2)).stringValue
        let timestamp = String(format: "%.3f", entry.timestamp.timeIntervalSinceReferenceDate)

        return [
            categoryID,
            timestamp,
            "\(entry.durationMinutes)",
            amount,
            unit,
            quantity,
            note,
            bonusKey,
            "\(entry.isManual)"
        ].joined(separator: "|")
    }
}
