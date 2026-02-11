import Foundation
import SwiftData

@Model
final class Entry {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var durationMinutes: Int = 0
    var amountUSD: Decimal = Decimal.zero
    var quantity: Decimal?
    var unit: CategoryUnit?
    var note: String = ""
    var bonusKey: String?
    var isManual: Bool = false
    var category: Category?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date.now,
        durationMinutes: Int,
        amountUSD: Decimal,
        category: Category?,
        note: String = "",
        bonusKey: String? = nil,
        isManual: Bool,
        quantity: Decimal? = nil,
        unit: CategoryUnit? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationMinutes = durationMinutes
        self.amountUSD = amountUSD
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.note = note
        self.bonusKey = bonusKey
        self.isManual = isManual
    }

    var resolvedUnit: CategoryUnit {
        if let unit {
            return unit
        }

        if durationMinutes > 0 {
            return .time
        }

        if let category {
            return category.resolvedUnit
        }

        return .money
    }

    var resolvedQuantity: Decimal {
        if let quantity, quantity > .zeroValue {
            return quantity
        }

        switch resolvedUnit {
        case .time:
            return Decimal(max(0, durationMinutes))
        case .count:
            return Decimal(max(0, durationMinutes))
        case .money:
            if amountUSD < .zeroValue {
                return amountUSD * Decimal(-1)
            }
            return amountUSD
        }
    }
}
