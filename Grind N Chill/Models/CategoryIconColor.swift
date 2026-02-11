import Foundation

enum CategoryIconColor: String, Codable, CaseIterable, Identifiable {
    case green
    case orange
    case blue
    case indigo
    case pink
    case red
    case teal
    case cyan
    case mint
    case yellow

    var id: String { rawValue }

    static func defaultColor(for type: CategoryType) -> CategoryIconColor {
        switch type {
        case .goodHabit:
            return .green
        case .quitHabit:
            return .orange
        }
    }
}
