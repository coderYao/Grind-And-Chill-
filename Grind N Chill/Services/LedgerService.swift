import Foundation

struct LedgerService {
    func earnedUSD(
        minutes: Int,
        usdPerHour: Decimal,
        categoryMultiplier: Double,
        categoryType: CategoryType
    ) -> Decimal {
        guard minutes > 0 else { return .zeroValue }

        let hourFraction = Decimal(minutes) / Decimal(60)
        let multiplierDecimal = Decimal(string: String(categoryMultiplier)) ?? Decimal(categoryMultiplier)
        var amount = (hourFraction * usdPerHour * multiplierDecimal).rounded(scale: 2)

        if categoryType == .quitHabit {
            amount *= Decimal(-1)
        }

        return amount
    }

    func balance(for entries: [Entry]) -> Decimal {
        entries.reduce(.zeroValue) { partialResult, entry in
            (partialResult + entry.amountUSD).rounded(scale: 2)
        }
    }
}
