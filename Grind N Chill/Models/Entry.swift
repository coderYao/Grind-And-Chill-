import Foundation
import SwiftData

@Model
final class Entry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var durationMinutes: Int
    var amountUSD: Decimal
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
        isManual: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.durationMinutes = durationMinutes
        self.amountUSD = amountUSD
        self.category = category
        self.note = note
        self.isManual = isManual
    }
}
