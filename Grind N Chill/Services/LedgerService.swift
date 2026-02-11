import Foundation

struct LedgerService {
    func amountUSD(for category: Category, quantity: Decimal, usdPerHour: Decimal) -> Decimal {
        guard quantity > .zeroValue else { return .zeroValue }

        let rawAmount: Decimal

        switch category.resolvedUnit {
        case .time:
            let hours = quantity / Decimal(60)

            switch category.resolvedTimeConversionMode {
            case .multiplier:
                let multiplierDecimal = decimal(from: category.multiplier, fallback: 1)
                rawAmount = hours * usdPerHour * multiplierDecimal
            case .hourlyRate:
                let customRate = category.resolvedHourlyRateUSD ?? usdPerHour
                rawAmount = hours * customRate
            }

        case .count:
            rawAmount = quantity * category.resolvedUSDPerCount

        case .money:
            rawAmount = quantity
        }

        return signed(rawAmount, for: category.resolvedType).rounded(scale: 2)
    }

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

    private func decimal(from value: Double, fallback: Double) -> Decimal {
        guard value > 0 else {
            return Decimal(string: String(fallback)) ?? Decimal(fallback)
        }

        return Decimal(string: String(value)) ?? Decimal(value)
    }

    private func signed(_ amount: Decimal, for categoryType: CategoryType) -> Decimal {
        switch categoryType {
        case .goodHabit:
            return amount
        case .quitHabit:
            return amount * Decimal(-1)
        }
    }
}
