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
        let streak = streakService.streak(for: category, entries: entries, now: now, calendar: calendar)

        guard streak > 0 else { return [] }

        let dayKey = now.isoDayString(calendar: calendar)
        let badgeID = "streak:\(category.id.uuidString)"
        var awards: [BadgeAward] = []

        for milestone in milestones where streak >= milestone {
            let key = "\(badgeID):\(milestone):\(dayKey)"

            let descriptor = FetchDescriptor<BadgeAward>(
                predicate: #Predicate { award in
                    award.awardKey == key
                }
            )

            if try modelContext.fetchCount(descriptor) == 0 {
                let award = BadgeAward(awardKey: key, dateAwarded: now)
                modelContext.insert(award)
                awards.append(award)
            }
        }

        return awards
    }
}
