import SwiftUI

extension CategoryIconColor {
    var swiftUIColor: Color {
        switch self {
        case .green:
            return .green
        case .orange:
            return .orange
        case .blue:
            return .blue
        case .indigo:
            return .indigo
        case .pink:
            return .pink
        case .red:
            return .red
        case .teal:
            return .teal
        case .cyan:
            return .cyan
        case .mint:
            return .mint
        case .yellow:
            return .yellow
        }
    }
}
