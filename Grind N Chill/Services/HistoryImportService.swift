import Foundation
import SwiftData

@MainActor
enum HistoryImportService {
    enum ConflictPolicy {
        case replaceExisting
        case keepExisting
    }

    struct PreviewReport: Equatable {
        var processedEntries = 0
        var entriesToCreate = 0
        var entriesToUpdate = 0
        var skippedEntries = 0
        var categoriesToCreate = 0

        var hasChanges: Bool {
            entriesToCreate > 0 || entriesToUpdate > 0 || categoriesToCreate > 0
        }
    }

    struct Report: Equatable {
        var processedEntries = 0
        var createdEntries = 0
        var updatedEntries = 0
        var skippedEntries = 0
        var createdCategories = 0
        var undoPayload: UndoPayload?
    }

    struct UndoEntrySnapshot: Codable, Equatable {
        let id: UUID
        let timestamp: Date
        let durationMinutes: Int
        let amountUSD: String
        let quantity: String?
        let unitRawValue: String?
        let note: String
        let isManual: Bool
        let categoryID: UUID?
    }

    struct UndoPayload: Codable, Equatable {
        let createdAt: Date
        let createdEntryIDs: [UUID]
        let createdCategoryIDs: [UUID]
        let updatedEntries: [UndoEntrySnapshot]
    }

    struct UndoReport: Equatable {
        var removedCreatedEntries = 0
        var revertedUpdatedEntries = 0
        var removedCreatedCategories = 0
        var missingRecords = 0
    }

    private struct ImportPayload: Decodable {
        let entries: [ImportEntry]
    }

    private struct ImportEntry: Decodable {
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

    private struct ParsedImportEntry {
        let id: UUID
        let timestamp: Date
        let categoryTitle: String
        let categoryType: CategoryType
        let unit: CategoryUnit
        let quantity: Decimal
        let durationMinutes: Int
        let amountUSD: Decimal
        let isManual: Bool
        let note: String
    }

    static func previewJSON(data: Data, modelContext: ModelContext) throws -> PreviewReport {
        let payload = try decodePayload(from: data)
        let existingCategories = try modelContext.fetch(FetchDescriptor<Category>())
        let existingEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        let analysis = analyze(
            payload: payload,
            existingCategories: existingCategories,
            existingEntries: existingEntries
        )
        return analysis.preview
    }

    static func importJSON(
        data: Data,
        modelContext: ModelContext,
        conflictPolicy: ConflictPolicy = .replaceExisting
    ) throws -> Report {
        let payload = try decodePayload(from: data)

        let existingCategories = try modelContext.fetch(FetchDescriptor<Category>())
        let existingEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        let analysis = analyze(
            payload: payload,
            existingCategories: existingCategories,
            existingEntries: existingEntries
        )

        var categoriesByKey = Dictionary(
            uniqueKeysWithValues: existingCategories.map { category in
                (
                    categoryKey(
                        title: category.title,
                        type: category.resolvedType,
                        unit: category.resolvedUnit
                    ),
                    category
                )
            }
        )

        var entriesByID = Dictionary(uniqueKeysWithValues: existingEntries.map { ($0.id, $0) })
        var createdEntryIDs: [UUID] = []
        var createdCategoryIDs = Set<UUID>()
        var updatedSnapshotsByID: [UUID: UndoEntrySnapshot] = [:]
        var report = Report(
            processedEntries: analysis.preview.processedEntries,
            createdEntries: 0,
            updatedEntries: 0,
            skippedEntries: analysis.preview.skippedEntries,
            createdCategories: analysis.preview.categoriesToCreate
        )

        for item in analysis.validEntries {
            let existingEntry = entriesByID[item.id]
            if existingEntry != nil, conflictPolicy == .keepExisting {
                report.skippedEntries += 1
                continue
            }

            let categoryResolution = resolveCategory(
                title: item.categoryTitle,
                type: item.categoryType,
                unit: item.unit,
                amountUSD: item.amountUSD,
                quantity: item.quantity,
                categoriesByKey: &categoriesByKey,
                modelContext: modelContext
            )
            let category = categoryResolution.category
            if categoryResolution.wasCreated {
                createdCategoryIDs.insert(category.id)
            }

            if let existingEntry {
                if updatedSnapshotsByID[item.id] == nil {
                    updatedSnapshotsByID[item.id] = snapshot(from: existingEntry)
                }
                existingEntry.timestamp = item.timestamp
                existingEntry.durationMinutes = item.durationMinutes
                existingEntry.amountUSD = item.amountUSD.rounded(scale: 2)
                existingEntry.quantity = item.quantity
                existingEntry.unit = item.unit
                existingEntry.category = category
                existingEntry.note = item.note
                existingEntry.isManual = item.isManual
                report.updatedEntries += 1
            } else {
                let entry = Entry(
                    id: item.id,
                    timestamp: item.timestamp,
                    durationMinutes: item.durationMinutes,
                    amountUSD: item.amountUSD.rounded(scale: 2),
                    category: category,
                    note: item.note,
                    isManual: item.isManual,
                    quantity: item.quantity,
                    unit: item.unit
                )
                modelContext.insert(entry)
                entriesByID[item.id] = entry
                createdEntryIDs.append(item.id)
                report.createdEntries += 1
            }
        }

        report.createdCategories = createdCategoryIDs.count
        report.undoPayload = buildUndoPayload(
            createdEntryIDs: createdEntryIDs,
            createdCategoryIDs: createdCategoryIDs,
            updatedSnapshotsByID: updatedSnapshotsByID
        )

        if modelContext.hasChanges {
            try modelContext.save()
        }

        return report
    }

    static func undoImport(_ payload: UndoPayload, modelContext: ModelContext) throws -> UndoReport {
        let entries = try modelContext.fetch(FetchDescriptor<Entry>())
        var entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let categories = try modelContext.fetch(FetchDescriptor<Category>())
        var categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var report = UndoReport()

        for entryID in payload.createdEntryIDs {
            guard let entry = entriesByID[entryID] else {
                report.missingRecords += 1
                continue
            }
            modelContext.delete(entry)
            entriesByID.removeValue(forKey: entryID)
            report.removedCreatedEntries += 1
        }

        for snapshot in payload.updatedEntries {
            guard let entry = entriesByID[snapshot.id] else {
                report.missingRecords += 1
                continue
            }

            entry.timestamp = snapshot.timestamp
            entry.durationMinutes = snapshot.durationMinutes
            entry.amountUSD = parseDecimal(snapshot.amountUSD) ?? entry.amountUSD
            if let quantityText = snapshot.quantity {
                entry.quantity = parseDecimal(quantityText)
            } else {
                entry.quantity = nil
            }
            if let unitRawValue = snapshot.unitRawValue {
                entry.unit = CategoryUnit(rawValue: unitRawValue)
            } else {
                entry.unit = nil
            }
            entry.note = snapshot.note
            entry.isManual = snapshot.isManual
            if let categoryID = snapshot.categoryID {
                entry.category = categoriesByID[categoryID]
            } else {
                entry.category = nil
            }
            report.revertedUpdatedEntries += 1
        }

        let remainingEntries = try modelContext.fetch(FetchDescriptor<Entry>())
        let usedCategoryIDs = Set(remainingEntries.compactMap { $0.category?.id })

        for categoryID in payload.createdCategoryIDs {
            guard let category = categoriesByID[categoryID] else {
                report.missingRecords += 1
                continue
            }
            guard usedCategoryIDs.contains(categoryID) == false else { continue }
            modelContext.delete(category)
            categoriesByID.removeValue(forKey: categoryID)
            report.removedCreatedCategories += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }

        return report
    }

    private static func resolveCategory(
        title: String,
        type: CategoryType,
        unit: CategoryUnit,
        amountUSD: Decimal,
        quantity: Decimal,
        categoriesByKey: inout [String: Category],
        modelContext: ModelContext
    ) -> (category: Category, wasCreated: Bool) {
        let normalizedTitle = normalizedCategoryTitle(title)
        let key = categoryKey(title: normalizedTitle, type: type, unit: unit)
        if let existing = categoriesByKey[key] {
            return (existing, false)
        }

        let inferredUSDPerCount: Double?
        if unit == .count, quantity > .zeroValue {
            let inferred = (absolute(amountUSD) / quantity).rounded(scale: 2)
            inferredUSDPerCount = NSDecimalNumber(decimal: inferred).doubleValue
        } else {
            inferredUSDPerCount = nil
        }

        let category = Category(
            title: normalizedTitle,
            multiplier: 1.0,
            type: type,
            dailyGoalMinutes: defaultDailyGoalMinutes(for: unit),
            symbolName: CategorySymbolCatalog.defaultSymbol(for: type),
            iconColor: CategoryIconColor.defaultColor(for: type),
            unit: unit,
            timeConversionMode: .multiplier,
            usdPerCount: inferredUSDPerCount
        )

        modelContext.insert(category)
        categoriesByKey[key] = category
        return (category, true)
    }

    private static func analyze(
        payload: ImportPayload,
        existingCategories: [Category],
        existingEntries: [Entry]
    ) -> (preview: PreviewReport, validEntries: [ParsedImportEntry]) {
        var preview = PreviewReport()
        var validEntries: [ParsedImportEntry] = []

        var categoryKeys = Set(
            existingCategories.map { category in
                categoryKey(
                    title: category.title,
                    type: category.resolvedType,
                    unit: category.resolvedUnit
                )
            }
        )
        var knownEntryIDs = Set(existingEntries.map(\.id))

        for item in payload.entries {
            preview.processedEntries += 1

            guard let entryID = UUID(uuidString: item.id) else {
                preview.skippedEntries += 1
                continue
            }

            let categoryType = CategoryType(rawValue: item.categoryType) ?? .goodHabit
            let unit = CategoryUnit(rawValue: item.unit) ?? .money
            let amountUSD = normalizedAmount(parseDecimal(item.amountUSD) ?? .zeroValue, for: categoryType)
            let durationMinutes = max(0, item.durationMinutes)
            let quantity = normalizedQuantity(
                parseDecimal(item.quantity),
                unit: unit,
                durationMinutes: durationMinutes,
                amountUSD: amountUSD
            )
            let timestamp = parseTimestamp(item.timestamp) ?? .now
            let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = normalizedCategoryTitle(item.categoryTitle)
            let key = categoryKey(title: normalizedTitle, type: categoryType, unit: unit)

            if categoryKeys.contains(key) == false {
                categoryKeys.insert(key)
                preview.categoriesToCreate += 1
            }

            if knownEntryIDs.contains(entryID) {
                preview.entriesToUpdate += 1
            } else {
                knownEntryIDs.insert(entryID)
                preview.entriesToCreate += 1
            }

            validEntries.append(
                ParsedImportEntry(
                    id: entryID,
                    timestamp: timestamp,
                    categoryTitle: normalizedTitle,
                    categoryType: categoryType,
                    unit: unit,
                    quantity: quantity,
                    durationMinutes: durationMinutes,
                    amountUSD: amountUSD,
                    isManual: item.isManual,
                    note: note
                )
            )
        }

        return (preview, validEntries)
    }

    private static func decodePayload(from data: Data) throws -> ImportPayload {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ImportPayload.self, from: data)
        } catch {
            throw ImportError.invalidPayload
        }
    }

    private static func parseDecimal(_ value: String) -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(string: trimmed)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        iso8601WithFractional.date(from: value) ?? iso8601.date(from: value)
    }

    private static func snapshot(from entry: Entry) -> UndoEntrySnapshot {
        UndoEntrySnapshot(
            id: entry.id,
            timestamp: entry.timestamp,
            durationMinutes: entry.durationMinutes,
            amountUSD: decimalString(entry.amountUSD),
            quantity: entry.quantity.map(decimalString),
            unitRawValue: entry.unit?.rawValue,
            note: entry.note,
            isManual: entry.isManual,
            categoryID: entry.category?.id
        )
    }

    private static func buildUndoPayload(
        createdEntryIDs: [UUID],
        createdCategoryIDs: Set<UUID>,
        updatedSnapshotsByID: [UUID: UndoEntrySnapshot]
    ) -> UndoPayload? {
        let sortedCreatedEntryIDs = createdEntryIDs.sorted { $0.uuidString < $1.uuidString }
        let sortedCreatedCategoryIDs = createdCategoryIDs.sorted { $0.uuidString < $1.uuidString }
        let sortedSnapshots = updatedSnapshotsByID.values.sorted { lhs, rhs in
            lhs.id.uuidString < rhs.id.uuidString
        }

        guard sortedCreatedEntryIDs.isEmpty == false
            || sortedCreatedCategoryIDs.isEmpty == false
            || sortedSnapshots.isEmpty == false else {
            return nil
        }

        return UndoPayload(
            createdAt: .now,
            createdEntryIDs: sortedCreatedEntryIDs,
            createdCategoryIDs: sortedCreatedCategoryIDs,
            updatedEntries: sortedSnapshots
        )
    }

    private static func normalizedAmount(_ amount: Decimal, for type: CategoryType) -> Decimal {
        if type == .quitHabit, amount > .zeroValue {
            return amount * Decimal(-1)
        }
        return amount
    }

    private static func normalizedQuantity(
        _ quantity: Decimal?,
        unit: CategoryUnit,
        durationMinutes: Int,
        amountUSD: Decimal
    ) -> Decimal {
        if let quantity, quantity > .zeroValue {
            return quantity.rounded(scale: 2)
        }

        switch unit {
        case .time, .count:
            return Decimal(max(0, durationMinutes))
        case .money:
            return absolute(amountUSD).rounded(scale: 2)
        }
    }

    private static func normalizedCategoryTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Imported Category" : trimmed
    }

    private static func categoryKey(title: String, type: CategoryType, unit: CategoryUnit) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(type.rawValue)|\(unit.rawValue)"
    }

    private static func defaultDailyGoalMinutes(for unit: CategoryUnit) -> Int {
        switch unit {
        case .time:
            return 30
        case .money:
            return 0
        case .count:
            return 10
        }
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < .zeroValue ? (value * Decimal(-1)) : value
    }

    private static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal.rounded(scale: 2)).stringValue
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    enum ImportError: LocalizedError {
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .invalidPayload:
                return "The selected file is not a valid Grind N Chill history export."
            }
        }
    }
}
