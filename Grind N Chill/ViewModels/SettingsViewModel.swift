import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    func normalizedUSDPerHour(_ input: Double) -> Double {
        let clamped = min(max(input, 0), 500)
        return (clamped * 100).rounded() / 100
    }

    func asDecimal(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }
}
