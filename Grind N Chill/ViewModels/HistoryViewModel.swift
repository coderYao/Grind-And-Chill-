import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryViewModel {
    enum DateRangeFilter: String, CaseIterable, Identifiable {
        case all
        case last7Days
        case last30Days
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .last7Days:
                return "7D"
            case .last30Days:
                return "30D"
            case .custom:
                return "Custom"
            }
        }
    }

    struct ExportDailySummary: Codable, Equatable {
        let date: String
        let ledgerChangeUSD: String
        let gainUSD: String
        let spentUSD: String
        let entryCount: Int
    }

    struct ExportEntry: Codable, Equatable {
        let id: String
        let timestamp: String
        let categoryTitle: String
        let categoryType: String
        let unit: String
        let quantity: String
        let durationMinutes: Int
        let amountUSD: String
        let isManual: Bool
        let note: String
    }

    struct ExportPayload: Codable, Equatable {
        let exportedAt: String
        let manualOnlyFilter: Bool
        let dateRangeFilter: String
        let dailySummaries: [ExportDailySummary]
        let entries: [ExportEntry]
    }

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
    var dateRangeFilter: DateRangeFilter = .all
    var customStartDate = Date.now
    var customEndDate = Date.now
    var canUndoLastImport = false
    var latestStatus: String?
    var latestError: String?
    private let undoStore: HistoryImportUndoStore

    init(undoStore: HistoryImportUndoStore = HistoryImportUndoStore()) {
        self.undoStore = undoStore
        canUndoLastImport = undoStore.load() != nil
    }

    var showsCustomDateRange: Bool {
        dateRangeFilter == .custom
    }

    func filteredEntries(
        from entries: [Entry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Entry] {
        let manualFiltered = showManualOnly ? entries.filter(\.isManual) : entries
        guard let bounds = dateBounds(now: now, calendar: calendar) else { return manualFiltered }
        return manualFiltered.filter { entry in
            entry.timestamp >= bounds.start && entry.timestamp <= bounds.end
        }
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

    func dailySummaryCSV(from summaries: [DailySummary], calendar: Calendar = .current) -> String {
        var lines = ["date,ledgerChangeUSD,gainUSD,spentUSD,entryCount"]
        let exportSummaries = exportDailySummaries(from: summaries, calendar: calendar)

        for summary in exportSummaries {
            lines.append(
                "\(summary.date),\(summary.ledgerChangeUSD),\(summary.gainUSD),\(summary.spentUSD),\(summary.entryCount)"
            )
        }

        return lines.joined(separator: "\n")
    }

    func exportJSON(
        from summaries: [DailySummary],
        manualOnlyFilter: Bool,
        dateRangeFilter: DateRangeFilter = .all,
        calendar: Calendar = .current
    ) throws -> String {
        let payload = ExportPayload(
            exportedAt: Self.exportTimestampFormatter.string(from: Date.now),
            manualOnlyFilter: manualOnlyFilter,
            dateRangeFilter: dateRangeFilter.rawValue,
            dailySummaries: exportDailySummaries(from: summaries, calendar: calendar),
            entries: exportEntries(from: summaries)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    func exportFilename(extension ext: String) -> String {
        let stamp = Self.fileNameStampFormatter.string(from: Date.now)
        return "grind-n-chill-history-\(stamp).\(ext)"
    }

    func deleteEntries(at offsets: IndexSet, from entries: [Entry], modelContext: ModelContext) {
        for index in offsets {
            modelContext.delete(entries[index])
        }

        do {
            try modelContext.save()
            latestStatus = "Deleted \(offsets.count) entr\(offsets.count == 1 ? "y" : "ies")."
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Could not delete entry: \(error.localizedDescription)"
        }
    }

    func importJSONData(
        _ data: Data,
        modelContext: ModelContext,
        conflictPolicy: HistoryImportService.ConflictPolicy = .replaceExisting
    ) {
        do {
            let report = try HistoryImportService.importJSON(
                data: data,
                modelContext: modelContext,
                conflictPolicy: conflictPolicy
            )
            if let payload = report.undoPayload {
                undoStore.save(payload)
                canUndoLastImport = true
            } else {
                undoStore.clear()
                canUndoLastImport = false
            }
            latestStatus = importSummaryText(report)
            latestError = nil
        } catch {
            latestStatus = nil
            if let localizedError = error as? LocalizedError,
               let description = localizedError.errorDescription {
                latestError = description
            } else {
                latestError = "Could not import history: \(error.localizedDescription)"
            }
        }
    }

    func previewImportJSONData(
        _ data: Data,
        modelContext: ModelContext
    ) -> HistoryImportService.PreviewReport? {
        do {
            let preview = try HistoryImportService.previewJSON(data: data, modelContext: modelContext)
            latestStatus = nil
            latestError = nil
            return preview
        } catch {
            latestStatus = nil
            if let localizedError = error as? LocalizedError,
               let description = localizedError.errorDescription {
                latestError = description
            } else {
                latestError = "Could not preview import: \(error.localizedDescription)"
            }
            return nil
        }
    }

    func undoLastImport(modelContext: ModelContext) {
        guard let payload = undoStore.load() else {
            latestStatus = nil
            latestError = "No import transaction is available to undo."
            canUndoLastImport = false
            return
        }

        do {
            let report = try HistoryImportService.undoImport(payload, modelContext: modelContext)
            undoStore.clear()
            canUndoLastImport = false
            latestStatus = undoSummaryText(report)
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Could not undo import: \(error.localizedDescription)"
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

    private func importSummaryText(_ report: HistoryImportService.Report) -> String {
        let created = report.createdEntries
        let updated = report.updatedEntries
        let skipped = report.skippedEntries
        let categories = report.createdCategories
        return "Imported \(created) new, updated \(updated), skipped \(skipped). Added \(categories) categories."
    }

    private func undoSummaryText(_ report: HistoryImportService.UndoReport) -> String {
        "Undo complete: removed \(report.removedCreatedEntries) entries, reverted \(report.revertedUpdatedEntries) updates, removed \(report.removedCreatedCategories) categories."
    }

    private func exportDailySummaries(
        from summaries: [DailySummary],
        calendar: Calendar
    ) -> [ExportDailySummary] {
        summaries.map { summary in
            ExportDailySummary(
                date: Self.exportDayFormatter(calendar: calendar).string(from: summary.date),
                ledgerChangeUSD: Self.decimalString(summary.ledgerChange),
                gainUSD: Self.decimalString(summary.gain),
                spentUSD: Self.decimalString(summary.spent),
                entryCount: summary.entries.count
            )
        }
    }

    private func exportEntries(from summaries: [DailySummary]) -> [ExportEntry] {
        summaries
            .flatMap(\.entries)
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
            .map { entry in
                ExportEntry(
                    id: entry.id.uuidString,
                    timestamp: Self.exportTimestampFormatter.string(from: entry.timestamp),
                    categoryTitle: entry.category?.title ?? "Unknown Category",
                    categoryType: entry.category?.resolvedType.rawValue ?? CategoryType.goodHabit.rawValue,
                    unit: entry.resolvedUnit.rawValue,
                    quantity: Self.decimalString(entry.resolvedQuantity),
                    durationMinutes: entry.durationMinutes,
                    amountUSD: Self.decimalString(entry.amountUSD),
                    isManual: entry.isManual,
                    note: entry.note
                )
            }
    }

    private static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal.rounded(scale: 2)).stringValue
    }

    private static func exportDayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static let exportTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileNameStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private func dateBounds(
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        switch dateRangeFilter {
        case .all:
            return nil
        case .last7Days:
            guard let startAnchor = calendar.date(byAdding: .day, value: -6, to: now) else {
                return nil
            }
            let start = calendar.startOfDay(for: startAnchor)
            return (start, endOfDay(for: now, calendar: calendar))
        case .last30Days:
            guard let startAnchor = calendar.date(byAdding: .day, value: -29, to: now) else {
                return nil
            }
            let start = calendar.startOfDay(for: startAnchor)
            return (start, endOfDay(for: now, calendar: calendar))
        case .custom:
            let startDate = min(customStartDate, customEndDate)
            let endDate = max(customStartDate, customEndDate)
            return (
                calendar.startOfDay(for: startDate),
                endOfDay(for: endDate, calendar: calendar)
            )
        }
    }

    private func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return date }
        return next.addingTimeInterval(-1)
    }
}
