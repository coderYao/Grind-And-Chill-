import Foundation

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case goodHabit
    case quitHabit

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .goodHabit:
            return "Good Habit"
        case .quitHabit:
            return "Quit Habit"
        }
    }

    var symbolName: String {
        switch self {
        case .goodHabit:
            return "book.fill"
        case .quitHabit:
            return "gamecontroller.fill"
        }
    }
}
