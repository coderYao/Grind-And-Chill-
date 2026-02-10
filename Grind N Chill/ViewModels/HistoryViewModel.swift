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

        if entry.note.isEmpty {
            return "\(mode) • \(entry.durationMinutes)m"
        }

        return "\(mode) • \(entry.durationMinutes)m • \(entry.note)"
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
}
