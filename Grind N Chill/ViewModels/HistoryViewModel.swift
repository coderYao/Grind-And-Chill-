import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryViewModel {
    struct DailySummary: Identifiable {
        let id: Date
        let date: Date
        let entries: [Entry]
        let ledgerChange: Decimal
        let gain: Decimal
        let spent: Decimal
    }

    struct DailyChartPoint: Identifiable {
        let id: Date
        let date: Date
        let ledgerChange: Double
        let gain: Double
        let spent: Double

        var spentAsNegative: Double {
            -spent
        }
    }

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

    func dailySummaries(from entries: [Entry], calendar: Calendar = .current) -> [DailySummary] {
        var grouped: [Date: [Entry]] = [:]

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            grouped[day, default: []].append(entry)
        }

        return grouped
            .map { day, dayEntries in
                let sortedEntries = dayEntries.sorted { lhs, rhs in
                    lhs.timestamp > rhs.timestamp
                }

                let totals = sortedEntries.reduce(
                    into: (
                        ledgerChange: Decimal.zeroValue,
                        gain: Decimal.zeroValue,
                        spent: Decimal.zeroValue
                    )
                ) { partialResult, entry in
                    partialResult.ledgerChange = (partialResult.ledgerChange + entry.amountUSD).rounded(scale: 2)

                    if entry.amountUSD >= .zeroValue {
                        partialResult.gain = (partialResult.gain + entry.amountUSD).rounded(scale: 2)
                    } else {
                        partialResult.spent = (
                            partialResult.spent + (entry.amountUSD * Decimal(-1))
                        ).rounded(scale: 2)
                    }
                }

                return DailySummary(
                    id: day,
                    date: day,
                    entries: sortedEntries,
                    ledgerChange: totals.ledgerChange,
                    gain: totals.gain,
                    spent: totals.spent
                )
            }
            .sorted { lhs, rhs in
                lhs.date > rhs.date
            }
    }

    func chartPoints(from summaries: [DailySummary], dayLimit: Int = 30) -> [DailyChartPoint] {
        Array(summaries.prefix(max(1, dayLimit)).reversed()).map { summary in
            DailyChartPoint(
                id: summary.id,
                date: summary.date,
                ledgerChange: NSDecimalNumber(decimal: summary.ledgerChange).doubleValue,
                gain: NSDecimalNumber(decimal: summary.gain).doubleValue,
                spent: NSDecimalNumber(decimal: summary.spent).doubleValue
            )
        }
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
