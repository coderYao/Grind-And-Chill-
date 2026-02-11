import Foundation
import SwiftData

@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var durationMinutes: Int
    var amountUSD: Decimal
    var quantity: Decimal?
    var unit: CategoryUnit?
    var note: String
    var isManual: Bool
    var category: Category

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        durationMinutes: Int,
        amountUSD: Decimal,
        category: Category,
        note: String = "",
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
        self.isManual = isManual
    }

    var resolvedUnit: CategoryUnit {
        if let unit {
            return unit
        }

        if durationMinutes > 0 {
            return .time
        }

        return category.resolvedUnit
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
