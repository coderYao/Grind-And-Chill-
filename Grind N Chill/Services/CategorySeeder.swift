import Foundation
import SwiftData

enum CategorySeeder {
    static func starterCategories() -> [Category] {
        [
            Category(
                title: "Deep Work",
                multiplier: 1.5,
                type: .goodHabit,
                dailyGoalMinutes: 120,
                symbolName: "brain.head.profile"
            ),
            Category(
                title: "Reading",
                multiplier: 1.1,
                type: .goodHabit,
                dailyGoalMinutes: 45,
                symbolName: "book.fill"
            ),
            Category(
                title: "Gaming Relapse",
                multiplier: 1.0,
                type: .quitHabit,
                dailyGoalMinutes: 0,
                symbolName: "gamecontroller.fill"
            )
        ]
    }

    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) throws {
        let existingCount = try modelContext.fetchCount(FetchDescriptor<Category>())

        guard existingCount == 0 else { return }

        starterCategories().forEach(modelContext.insert)
        try modelContext.save()
    }
}
