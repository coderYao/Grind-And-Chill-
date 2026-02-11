import Foundation
import SwiftData

struct BadgeService {
    var milestones: [Int] = [3, 7, 30]
    private let streakService = StreakService()

    @MainActor
    func awardBadgesIfNeeded(
        for category: Category,
        entries: [Entry],
        modelContext: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [BadgeAward] {
        guard category.resolvedStreakEnabled else {
            return []
        }

        let badgeEnabled = category.resolvedBadgeEnabled
        let bonusEnabled = category.resolvedStreakBonusEnabled
        let resolvedMilestones = category.resolvedBadgeMilestones(defaults: milestones)
        let bonusSchedule = category.resolvedStreakBonusAmounts(defaultMilestones: resolvedMilestones)
        let hasConfiguredBonus = resolvedMilestones.contains { milestone in
            (bonusSchedule[milestone] ?? .zeroValue) > .zeroValue
        }

        guard badgeEnabled || (bonusEnabled && hasConfiguredBonus) else {
            return []
        }

        let streak = streakService.streak(for: category, entries: entries, now: now, calendar: calendar)

        guard streak > 0 else { return [] }

        let dayKey = now.isoDayString(calendar: calendar)
        let badgeID = "streak:\(category.id.uuidString)"
        var awards: [BadgeAward] = []

        for milestone in resolvedMilestones where streak >= milestone {
            let key = "\(badgeID):\(milestone):\(dayKey)"
            let shouldSkip: Bool

            if badgeEnabled {
                let existingBadgeDescriptor = FetchDescriptor<BadgeAward>(
                    predicate: #Predicate { award in
                        award.awardKey == key
                    }
                )
                shouldSkip = try modelContext.fetchCount(existingBadgeDescriptor) > 0
            } else {
                let existingBonusDescriptor = FetchDescriptor<Entry>(
                    predicate: #Predicate { entry in
                        entry.bonusKey == key
                    }
                )
                shouldSkip = try modelContext.fetchCount(existingBonusDescriptor) > 0
            }

            guard shouldSkip == false else { continue }

            if badgeEnabled {
                let award = BadgeAward(awardKey: key, dateAwarded: now)
                modelContext.insert(award)
                awards.append(award)
            }

            if bonusEnabled, let bonusAmount = bonusSchedule[milestone], bonusAmount > .zeroValue {
                let roundedBonusAmount = bonusAmount.rounded(scale: 2)
                let bonusEntry = Entry(
                    timestamp: now,
                    durationMinutes: 0,
                    amountUSD: roundedBonusAmount,
                    category: category,
                    note: "Streak bonus (\(milestone)d)",
                    bonusKey: key,
                    isManual: true,
                    quantity: roundedBonusAmount,
                    unit: .money
                )
                modelContext.insert(bonusEntry)
            }
        }

        return awards
    }
}
