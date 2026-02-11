import Foundation

enum CategoryUnit: String, Codable, CaseIterable, Identifiable {
    case time
    case money
    case count

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .time:
            return "Time"
        case .money:
            return "Money"
        case .count:
            return "Count"
        }
    }
}
