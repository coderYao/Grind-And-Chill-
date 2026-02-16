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

    struct CategoryMoneySlice: Identifiable {
        let id: String
        let title: String
        let symbolName: String
        let iconColor: CategoryIconColor?
        let totalAmountUSD: Decimal
        let entryCount: Int
    }

    struct ManualEntryDraft: Identifiable, Equatable {
        let id: UUID
        let categoryTitle: String
        let unit: CategoryUnit
        let categoryType: CategoryType
        var timestamp: Date
        var amountInput: Double
        var countInput: Double
        var durationMinutes: Int
        var note: String
    }

    struct DeletedEntrySnapshot: Codable, Equatable {
        let id: UUID
        let timestamp: Date
        let durationMinutes: Int
        let amountUSD: String
        let quantity: String?
        let unitRawValue: String?
        let note: String
        let bonusKey: String?
        let isManual: Bool
        let categoryID: UUID?
    }

    struct DeleteUndoPayload: Codable, Equatable {
        let deletedAt: Date
        let entries: [DeletedEntrySnapshot]
    }

    var showManualOnly = false
    var dateRangeFilter: DateRangeFilter = .all
    var customStartDate = Date.now
    var customEndDate = Date.now
    var canUndoLastImport = false
    var canUndoLastDelete = false
    var latestStatus: String?
    var latestError: String?
    private let importUndoStore: HistoryImportUndoStore
    private let deleteUndoStore: HistoryDeleteUndoStore
    private let ledgerService = LedgerService()

    init(
        importUndoStore: HistoryImportUndoStore = HistoryImportUndoStore(),
        deleteUndoStore: HistoryDeleteUndoStore = HistoryDeleteUndoStore()
    ) {
        self.importUndoStore = importUndoStore
        self.deleteUndoStore = deleteUndoStore
        canUndoLastImport = importUndoStore.load() != nil
        canUndoLastDelete = deleteUndoStore.load() != nil
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

    func categoryMoneyBreakdown(
        from entries: [Entry]
    ) -> (grind: [CategoryMoneySlice], chill: [CategoryMoneySlice], grindTotal: Decimal, chillTotal: Decimal) {
        struct Bucket {
            let id: String
            let title: String
            let symbolName: String
            let iconColor: CategoryIconColor?
            var grindTotal: Decimal
            var chillTotal: Decimal
            var grindEntryCount: Int
            var chillEntryCount: Int
        }

        var buckets: [String: Bucket] = [:]

        for entry in entries {
            let categoryID = entry.category?.id.uuidString ?? "unknown"
            let title = entry.category?.title ?? "Unknown Category"
            let symbol = entry.category?.resolvedSymbolName ?? "tray"
            let color = entry.category?.resolvedIconColor
            let bucketID = "\(categoryID)|\(title)"

            if buckets[bucketID] == nil {
                buckets[bucketID] = Bucket(
                    id: bucketID,
                    title: title,
                    symbolName: symbol,
                    iconColor: color,
                    grindTotal: .zeroValue,
                    chillTotal: .zeroValue,
                    grindEntryCount: 0,
                    chillEntryCount: 0
                )
            }

            guard var bucket = buckets[bucketID] else { continue }
            if entry.amountUSD >= .zeroValue {
                bucket.grindTotal = (bucket.grindTotal + entry.amountUSD).rounded(scale: 2)
                bucket.grindEntryCount += 1
            } else {
                bucket.chillTotal = (bucket.chillTotal + absolute(entry.amountUSD)).rounded(scale: 2)
                bucket.chillEntryCount += 1
            }
            buckets[bucketID] = bucket
        }

        let grind = buckets.values
            .filter { $0.grindTotal > .zeroValue }
            .map { bucket in
                CategoryMoneySlice(
                    id: "grind:\(bucket.id)",
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.grindTotal,
                    entryCount: bucket.grindEntryCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalAmountUSD != rhs.totalAmountUSD {
                    return lhs.totalAmountUSD > rhs.totalAmountUSD
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let chill = buckets.values
            .filter { $0.chillTotal > .zeroValue }
            .map { bucket in
                CategoryMoneySlice(
                    id: "chill:\(bucket.id)",
                    title: bucket.title,
                    symbolName: bucket.symbolName,
                    iconColor: bucket.iconColor,
                    totalAmountUSD: bucket.chillTotal,
                    entryCount: bucket.chillEntryCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalAmountUSD != rhs.totalAmountUSD {
                    return lhs.totalAmountUSD > rhs.totalAmountUSD
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let grindTotal = grind.reduce(.zeroValue) { partialResult, slice in
            (partialResult + slice.totalAmountUSD).rounded(scale: 2)
        }
        let chillTotal = chill.reduce(.zeroValue) { partialResult, slice in
            (partialResult + slice.totalAmountUSD).rounded(scale: 2)
        }

        return (grind, chill, grindTotal, chillTotal)
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
        do {
            let entriesToDelete = offsets.map { entries[$0] }
            let payload = DeleteUndoPayload(
                deletedAt: .now,
                entries: entriesToDelete.map(snapshot(from:))
            )

            for entry in entriesToDelete {
                modelContext.delete(entry)
            }

            try modelContext.save()
            deleteUndoStore.save(payload)
            canUndoLastDelete = true
            latestStatus = "Deleted \(offsets.count) entr\(offsets.count == 1 ? "y" : "ies")."
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Could not delete entry: \(error.localizedDescription)"
        }
    }

    func undoLastDelete(modelContext: ModelContext) {
        guard let payload = deleteUndoStore.load() else {
            canUndoLastDelete = false
            latestStatus = nil
            latestError = "No deleted entry is available to undo."
            return
        }

        do {
            let existingEntries = try modelContext.fetch(FetchDescriptor<Entry>())
            var existingIDs = Set(existingEntries.map(\.id))
            let categories = try modelContext.fetch(FetchDescriptor<Category>())
            let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

            var restored = 0
            var skipped = 0

            for snapshot in payload.entries {
                if existingIDs.contains(snapshot.id) {
                    skipped += 1
                    continue
                }

                let restoredEntry = Entry(
                    id: snapshot.id,
                    timestamp: snapshot.timestamp,
                    durationMinutes: snapshot.durationMinutes,
                    amountUSD: decimal(from: snapshot.amountUSD) ?? .zeroValue,
                    category: snapshot.categoryID.flatMap { categoriesByID[$0] },
                    note: snapshot.note,
                    bonusKey: snapshot.bonusKey,
                    isManual: snapshot.isManual,
                    quantity: snapshot.quantity.flatMap(decimal(from:)),
                    unit: snapshot.unitRawValue.flatMap(CategoryUnit.init(rawValue:))
                )
                modelContext.insert(restoredEntry)
                existingIDs.insert(snapshot.id)
                restored += 1
            }

            try modelContext.save()
            deleteUndoStore.clear()
            canUndoLastDelete = false
            latestStatus = "Undo complete: restored \(restored), skipped \(skipped)."
            latestError = nil
        } catch {
            latestStatus = nil
            latestError = "Could not undo delete: \(error.localizedDescription)"
        }
    }

    func entryDraft(for entry: Entry) -> ManualEntryDraft? {
        if entry.bonusKey != nil {
            return nil
        }

        let categoryType = entry.category?.resolvedType ?? .goodHabit
        let unit = entry.resolvedUnit
        let categoryTitle = entry.category?.title ?? "Unknown Category"
        let absAmount = absolute(entry.amountUSD)
        let quantity = entry.resolvedQuantity

        switch unit {
        case .time:
            return ManualEntryDraft(
                id: entry.id,
                categoryTitle: categoryTitle,
                unit: .time,
                categoryType: categoryType,
                timestamp: entry.timestamp,
                amountInput: NSDecimalNumber(decimal: absAmount).doubleValue,
                countInput: NSDecimalNumber(decimal: quantity).doubleValue,
                durationMinutes: max(1, entry.durationMinutes),
                note: entry.note
            )
        case .count:
            return ManualEntryDraft(
                id: entry.id,
                categoryTitle: categoryTitle,
                unit: .count,
                categoryType: categoryType,
                timestamp: entry.timestamp,
                amountInput: NSDecimalNumber(decimal: absAmount).doubleValue,
                countInput: NSDecimalNumber(decimal: quantity).doubleValue,
                durationMinutes: entry.durationMinutes,
                note: entry.note
            )
        case .money:
            return ManualEntryDraft(
                id: entry.id,
                categoryTitle: categoryTitle,
                unit: .money,
                categoryType: categoryType,
                timestamp: entry.timestamp,
                amountInput: NSDecimalNumber(decimal: absAmount).doubleValue,
                countInput: NSDecimalNumber(decimal: quantity).doubleValue,
                durationMinutes: entry.durationMinutes,
                note: entry.note
            )
        }
    }

    func manualDraft(for entry: Entry) -> ManualEntryDraft? {
        entryDraft(for: entry)
    }

    @discardableResult
    func saveEntryEdit(
        _ draft: ManualEntryDraft,
        entries: [Entry],
        modelContext: ModelContext,
        usdPerHour: Decimal
    ) -> Bool {
        guard let entry = entries.first(where: { $0.id == draft.id }) else {
            latestStatus = nil
            latestError = "Could not find entry to edit."
            return false
        }

        guard entry.bonusKey == nil else {
            latestStatus = nil
            latestError = "Streak bonus entries can't be edited."
            return false
        }

        guard let category = entry.category else {
            latestStatus = nil
            latestError = "Entry is missing its category."
            return false
        }

        let quantity: Decimal
        let durationMinutes: Int

        switch draft.unit {
        case .time:
            guard draft.durationMinutes > 0, draft.durationMinutes <= 1_440 else {
                latestStatus = nil
                latestError = "Duration must be between 1 and 1440 minutes."
                return false
            }
            durationMinutes = draft.durationMinutes
            quantity = Decimal(durationMinutes)
        case .count:
            guard draft.countInput > 0 else {
                latestStatus = nil
                latestError = "Count must be greater than zero."
                return false
            }
            durationMinutes = 0
            quantity = decimal(from: draft.countInput) ?? .zeroValue
        case .money:
            guard draft.amountInput > 0 else {
                latestStatus = nil
                latestError = "Amount must be greater than zero."
                return false
            }
            durationMinutes = 0
            quantity = decimal(from: draft.amountInput) ?? .zeroValue
        }

        let amount = ledgerService.amountUSD(
            for: category,
            quantity: quantity,
            usdPerHour: usdPerHour
        )

        entry.durationMinutes = durationMinutes
        entry.quantity = quantity
        entry.unit = draft.unit
        entry.timestamp = draft.timestamp
        entry.amountUSD = amount
        entry.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try modelContext.save()
            latestStatus = "Entry updated."
            latestError = nil
            return true
        } catch {
            latestStatus = nil
            latestError = "Could not save edited entry: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveManualEdit(
        _ draft: ManualEntryDraft,
        entries: [Entry],
        modelContext: ModelContext,
        usdPerHour: Decimal
    ) -> Bool {
        saveEntryEdit(
            draft,
            entries: entries,
            modelContext: modelContext,
            usdPerHour: usdPerHour
        )
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
                importUndoStore.save(payload)
                canUndoLastImport = true
            } else {
                importUndoStore.clear()
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
        guard let payload = importUndoStore.load() else {
            latestStatus = nil
            latestError = "No import transaction is available to undo."
            canUndoLastImport = false
            return
        }

        do {
            let report = try HistoryImportService.undoImport(payload, modelContext: modelContext)
            importUndoStore.clear()
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

    private func snapshot(from entry: Entry) -> DeletedEntrySnapshot {
        DeletedEntrySnapshot(
            id: entry.id,
            timestamp: entry.timestamp,
            durationMinutes: entry.durationMinutes,
            amountUSD: Self.decimalString(entry.amountUSD),
            quantity: entry.quantity.map(Self.decimalString),
            unitRawValue: entry.unit?.rawValue,
            note: entry.note,
            bonusKey: entry.bonusKey,
            isManual: entry.isManual,
            categoryID: entry.category?.id
        )
    }

    private func decimal(from value: Double) -> Decimal? {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    private func decimal(from text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(string: text)
    }

    private func absolute(_ value: Decimal) -> Decimal {
        value < .zeroValue ? (value * Decimal(-1)) : value
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
