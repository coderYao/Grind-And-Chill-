import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var title: String = ""
    var multiplier: Double = 1.0
    var type: CategoryType? = CategoryType.goodHabit
    var dailyGoalMinutes: Int = 0
    var symbolName: String?
    @Relationship(deleteRule: .cascade) var entries: [Entry]

    init(
        id: UUID = UUID(),
        title: String,
        multiplier: Double,
        type: CategoryType,
        dailyGoalMinutes: Int,
        symbolName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.multiplier = multiplier
        self.type = type
        self.dailyGoalMinutes = dailyGoalMinutes
        self.symbolName = symbolName
        self.entries = []
    }

    var resolvedType: CategoryType {
        type ?? .goodHabit
    }

    var resolvedSymbolName: String {
        symbolName ?? resolvedType.symbolName
    }
}
