import Foundation

enum CategorySymbolCatalog {
    private static let goodHabitSymbols = [
        "book.fill",
        "brain.head.profile",
        "figure.run",
        "laptopcomputer",
        "checkmark.seal.fill",
        "dumbbell.fill",
        "sun.max.fill",
        "fork.knife"
    ]

    private static let quitHabitSymbols = [
        "gamecontroller.fill",
        "wifi.slash",
        "nosign",
        "smoke.fill",
        "cup.and.saucer.fill",
        "sparkles",
        "hourglass",
        "moon.zzz.fill"
    ]

    static func symbols(for type: CategoryType) -> [String] {
        switch type {
        case .goodHabit:
            return goodHabitSymbols
        case .quitHabit:
            return quitHabitSymbols
        }
    }

    static func defaultSymbol(for type: CategoryType) -> String {
        symbols(for: type).first ?? type.symbolName
    }

    static func normalizedSymbol(_ symbolName: String, for type: CategoryType) -> String {
        let options = symbols(for: type)

        if options.contains(symbolName) {
            return symbolName
        }

        return defaultSymbol(for: type)
    }
}
