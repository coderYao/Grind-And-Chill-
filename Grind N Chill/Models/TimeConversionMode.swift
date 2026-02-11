import Foundation

enum TimeConversionMode: String, Codable, CaseIterable, Identifiable {
    case multiplier
    case hourlyRate

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .multiplier:
            return "Multiplier"
        case .hourlyRate:
            return "Hourly Rate"
        }
    }
}
