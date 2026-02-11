import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryViewModel {
    var showManualOnly = false
    var latestError: String?

    func filteredEntries(from entries: [Entry]) -> [Entry] {
        guard showManualOnly else { return entries }
        return entries.filter(\.isManual)
    }

    func subtitle(for entry: Entry) -> String {
        let mode = entry.isManual ? "Manual" : "Timer"
        let metric = quantityLabel(for: entry)

        if entry.note.isEmpty {
            return "\(mode) • \(metric)"
        }

        return "\(mode) • \(metric) • \(entry.note)"
    }

    func deleteEntries(at offsets: IndexSet, from entries: [Entry], modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(entries[index])
        }

        do {
            try modelContext.save()
            latestError = nil
        } catch {
            latestError = "Could not delete entry: \(error.localizedDescription)"
        }
    }

    private func quantityLabel(for entry: Entry) -> String {
        switch entry.resolvedUnit {
        case .time:
            return "\(entry.durationMinutes)m"
        case .count:
            let quantity = NSDecimalNumber(decimal: entry.resolvedQuantity).doubleValue
            return quantity.formatted(.number.precision(.fractionLength(0 ... 2)))
        case .money:
            return entry.resolvedQuantity.formatted(.currency(code: "USD"))
        }
    }
}
