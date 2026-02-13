import Foundation
import Observation
import CoreData
import CloudKit
import SwiftData

enum GrindNChillSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Category.self, Entry.self, BadgeAward.self, SyncEventHistory.self]
    }

    @Model
    final class Category {
        var id: UUID = UUID()
        var title: String = ""
        var multiplier: Double = 1.0
        var type: CategoryType?
        var unit: CategoryUnit?
        var timeConversionMode: TimeConversionMode?
        var hourlyRateUSD: Double?
        var usdPerCount: Double?
        var dailyGoalMinutes: Int = 0
        var streakEnabled: Bool?
        var badgeEnabled: Bool?
        var badgeMilestones: String?
        var streakBonusEnabled: Bool?
        var streakBonusAmountUSD: Double?
        var streakBonusSchedule: String?
        var symbolName: String?
        var iconColor: CategoryIconColor?
        @Relationship(deleteRule: .cascade, inverse: \Entry.category) var entries: [Entry]?

        init(
            id: UUID = UUID(),
            title: String = "",
            multiplier: Double = 1.0,
            type: CategoryType? = nil,
            unit: CategoryUnit? = nil,
            timeConversionMode: TimeConversionMode? = nil,
            hourlyRateUSD: Double? = nil,
            usdPerCount: Double? = nil,
            dailyGoalMinutes: Int = 0,
            streakEnabled: Bool? = nil,
            badgeEnabled: Bool? = nil,
            badgeMilestones: String? = nil,
            streakBonusEnabled: Bool? = nil,
            streakBonusAmountUSD: Double? = nil,
            streakBonusSchedule: String? = nil,
            symbolName: String? = nil,
            iconColor: CategoryIconColor? = nil,
            entries: [Entry]? = nil
        ) {
            self.id = id
            self.title = title
            self.multiplier = multiplier
            self.type = type
            self.unit = unit
            self.timeConversionMode = timeConversionMode
            self.hourlyRateUSD = hourlyRateUSD
            self.usdPerCount = usdPerCount
            self.dailyGoalMinutes = dailyGoalMinutes
            self.streakEnabled = streakEnabled
            self.badgeEnabled = badgeEnabled
            self.badgeMilestones = badgeMilestones
            self.streakBonusEnabled = streakBonusEnabled
            self.streakBonusAmountUSD = streakBonusAmountUSD
            self.streakBonusSchedule = streakBonusSchedule
            self.symbolName = symbolName
            self.iconColor = iconColor
            self.entries = entries
        }
    }

    @Model
    final class Entry {
        var id: UUID = UUID()
        var timestamp: Date = Date.now
        var durationMinutes: Int = 0
        var amountUSD: Decimal = 0
        var quantity: Decimal?
        var unit: CategoryUnit?
        var note: String = ""
        var bonusKey: String?
        var isManual: Bool = false
        var category: Category?

        init(
            id: UUID = UUID(),
            timestamp: Date = Date.now,
            durationMinutes: Int = 0,
            amountUSD: Decimal = 0,
            quantity: Decimal? = nil,
            unit: CategoryUnit? = nil,
            note: String = "",
            bonusKey: String? = nil,
            isManual: Bool = false,
            category: Category? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.durationMinutes = durationMinutes
            self.amountUSD = amountUSD
            self.quantity = quantity
            self.unit = unit
            self.note = note
            self.bonusKey = bonusKey
            self.isManual = isManual
            self.category = category
        }
    }

    @Model
    final class BadgeAward {
        var awardKey: String = ""
        var dateAwarded: Date = Date.now

        init(
            awardKey: String = "",
            dateAwarded: Date = Date.now
        ) {
            self.awardKey = awardKey
            self.dateAwarded = dateAwarded
        }
    }

    @Model
    final class SyncEventHistory {
        var id: UUID = UUID()
        var eventIdentifier: String = ""
        var kindRaw: String = ""
        var outcomeRaw: String = ""
        var startedAt: Date = Date.now
        var endedAt: Date?
        var detail: String?

        init(
            id: UUID = UUID(),
            eventIdentifier: String = "",
            kindRaw: String = "",
            outcomeRaw: String = "",
            startedAt: Date = Date.now,
            endedAt: Date? = nil,
            detail: String? = nil
        ) {
            self.id = id
            self.eventIdentifier = eventIdentifier
            self.kindRaw = kindRaw
            self.outcomeRaw = outcomeRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.detail = detail
        }
    }
}

enum GrindNChillSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Category.self, Entry.self, BadgeAward.self, SyncEventHistory.self]
    }
}

enum GrindNChillMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GrindNChillSchemaV1.self, GrindNChillSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: GrindNChillSchemaV1.self,
                toVersion: GrindNChillSchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in
                    try applyPostMigrationDefaults(in: context)
                }
            )
        ]
    }

    private struct RepairSummary {
        var categoriesRepaired = 0
        var entriesRepaired = 0
        var badgeAwardsRepaired = 0
        var badgeAwardsDeduped = 0
        var syncEventsRepaired = 0
        var syncEventsDeduped = 0
    }

    static func repairStoreDataIfNeeded(in context: ModelContext) throws {
        try applyPostMigrationDefaults(in: context)
    }

#if DEBUG
    static func applyPostMigrationDefaultsForTesting(in context: ModelContext) throws {
        try applyPostMigrationDefaults(in: context)
    }
#endif

    private static func applyPostMigrationDefaults(in context: ModelContext) throws {
        var summary = RepairSummary()

        let categories = try context.fetch(FetchDescriptor<Category>())
        for category in categories {
            let trimmedTitle = category.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.isEmpty {
                category.title = "Category"
                summary.categoriesRepaired += 1
            } else if trimmedTitle != category.title {
                category.title = trimmedTitle
                summary.categoriesRepaired += 1
            }

            if category.multiplier <= 0 {
                category.multiplier = 1.0
                summary.categoriesRepaired += 1
            }
            if category.dailyGoalMinutes < 0 {
                category.dailyGoalMinutes = 0
                summary.categoriesRepaired += 1
            }

            if category.type == nil {
                category.type = .goodHabit
                summary.categoriesRepaired += 1
            }
            if category.unit == nil {
                category.unit = .time
                summary.categoriesRepaired += 1
            }

            let resolvedType = category.type ?? .goodHabit
            let normalizedSymbol = CategorySymbolCatalog.normalizedSymbol(category.symbolName ?? "", for: resolvedType)
            if category.symbolName != normalizedSymbol {
                category.symbolName = normalizedSymbol
                summary.categoriesRepaired += 1
            }
            if category.iconColor == nil {
                category.iconColor = CategoryIconColor.defaultColor(for: resolvedType)
                summary.categoriesRepaired += 1
            }

            if category.streakEnabled == nil {
                category.streakEnabled = true
                summary.categoriesRepaired += 1
            }
            if category.badgeEnabled == nil {
                category.badgeEnabled = true
                summary.categoriesRepaired += 1
            }
            if category.streakBonusEnabled == nil {
                category.streakBonusEnabled = false
                summary.categoriesRepaired += 1
            }
            if category.badgeMilestones?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                category.badgeMilestones = nil
                summary.categoriesRepaired += 1
            }
            if category.streakBonusSchedule?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                category.streakBonusSchedule = nil
                summary.categoriesRepaired += 1
            }

            let resolvedUnit = category.unit ?? .time
            switch resolvedUnit {
            case .time:
                if category.timeConversionMode == nil {
                    category.timeConversionMode = .multiplier
                    summary.categoriesRepaired += 1
                }
            case .money, .count:
                if category.timeConversionMode != nil {
                    category.timeConversionMode = nil
                    summary.categoriesRepaired += 1
                }
                if category.hourlyRateUSD != nil {
                    category.hourlyRateUSD = nil
                    summary.categoriesRepaired += 1
                }
            }

            if let usdPerCount = category.usdPerCount, usdPerCount <= 0 {
                category.usdPerCount = nil
                summary.categoriesRepaired += 1
            }
            if let hourlyRateUSD = category.hourlyRateUSD, hourlyRateUSD <= 0 {
                category.hourlyRateUSD = nil
                summary.categoriesRepaired += 1
            }
            if let streakBonusAmountUSD = category.streakBonusAmountUSD, streakBonusAmountUSD <= 0 {
                category.streakBonusAmountUSD = nil
                summary.categoriesRepaired += 1
            }
        }

        let entries = try context.fetch(FetchDescriptor<Entry>())
        for entry in entries {
            if entry.durationMinutes < 0 {
                entry.durationMinutes = 0
                summary.entriesRepaired += 1
            }

            let normalizedNote = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.note != normalizedNote {
                entry.note = normalizedNote
                summary.entriesRepaired += 1
            }

            if entry.bonusKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                entry.bonusKey = nil
                summary.entriesRepaired += 1
            }

            if entry.unit == nil {
                if let category = entry.category {
                    entry.unit = category.resolvedUnit
                } else if entry.durationMinutes > 0 {
                    entry.unit = .time
                } else {
                    entry.unit = .money
                }
                summary.entriesRepaired += 1
            }

            if let category = entry.category, category.resolvedType == .quitHabit, entry.amountUSD > .zeroValue {
                entry.amountUSD = entry.amountUSD * Decimal(-1)
                summary.entriesRepaired += 1
            }

            if entry.quantity == nil || (entry.quantity ?? .zeroValue) < .zeroValue {
                switch entry.unit ?? .money {
                case .time, .count:
                    entry.quantity = Decimal(max(0, entry.durationMinutes))
                case .money:
                    entry.quantity = entry.amountUSD < .zeroValue ? (entry.amountUSD * Decimal(-1)) : entry.amountUSD
                }
                summary.entriesRepaired += 1
            }
        }

        let badgeAwards = try context.fetch(FetchDescriptor<BadgeAward>())
        var badgeAwardsByKey: [String: BadgeAward] = [:]
        var duplicateBadgeAwards: [BadgeAward] = []
        for award in badgeAwards {
            let trimmedAwardKey = award.awardKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedKey = trimmedAwardKey.isEmpty ? "badge:\(UUID().uuidString)" : trimmedAwardKey
            if award.awardKey != normalizedKey {
                award.awardKey = normalizedKey
                summary.badgeAwardsRepaired += 1
            }

            if let existing = badgeAwardsByKey[normalizedKey] {
                let shouldKeepCurrent = award.dateAwarded < existing.dateAwarded
                if shouldKeepCurrent {
                    duplicateBadgeAwards.append(existing)
                    badgeAwardsByKey[normalizedKey] = award
                } else {
                    duplicateBadgeAwards.append(award)
                }
            } else {
                badgeAwardsByKey[normalizedKey] = award
            }
        }
        for duplicate in duplicateBadgeAwards {
            context.delete(duplicate)
            summary.badgeAwardsDeduped += 1
        }

        let syncEvents = try context.fetch(FetchDescriptor<SyncEventHistory>())
        var syncEventsByIdentifier: [String: SyncEventHistory] = [:]
        var duplicateSyncEvents: [SyncEventHistory] = []
        for event in syncEvents {
            let trimmedEventIdentifier = event.eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedIdentifier = trimmedEventIdentifier.isEmpty ? UUID().uuidString : trimmedEventIdentifier
            if event.eventIdentifier != normalizedIdentifier {
                event.eventIdentifier = normalizedIdentifier
                summary.syncEventsRepaired += 1
            }

            if event.kindRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                event.kindRaw = "Sync"
                summary.syncEventsRepaired += 1
            }
            if event.outcomeRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                event.outcomeRaw = "inProgress"
                summary.syncEventsRepaired += 1
            }
            if let endedAt = event.endedAt, endedAt < event.startedAt {
                event.endedAt = event.startedAt
                summary.syncEventsRepaired += 1
            }
            if event.recordedAt < event.startedAt {
                event.recordedAt = event.endedAt ?? event.startedAt
                summary.syncEventsRepaired += 1
            }
            if event.detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                event.detail = nil
                summary.syncEventsRepaired += 1
            }

            if let existing = syncEventsByIdentifier[normalizedIdentifier] {
                let existingRank = (existing.recordedAt, existing.endedAt ?? existing.startedAt, existing.id.uuidString)
                let currentRank = (event.recordedAt, event.endedAt ?? event.startedAt, event.id.uuidString)
                if currentRank > existingRank {
                    duplicateSyncEvents.append(existing)
                    syncEventsByIdentifier[normalizedIdentifier] = event
                } else {
                    duplicateSyncEvents.append(event)
                }
            } else {
                syncEventsByIdentifier[normalizedIdentifier] = event
            }
        }
        for duplicate in duplicateSyncEvents {
            context.delete(duplicate)
            summary.syncEventsDeduped += 1
        }

        if context.hasChanges {
            try context.save()
        }

#if DEBUG
        if summary.categoriesRepaired > 0 ||
            summary.entriesRepaired > 0 ||
            summary.badgeAwardsRepaired > 0 ||
            summary.badgeAwardsDeduped > 0 ||
            summary.syncEventsRepaired > 0 ||
            summary.syncEventsDeduped > 0 {
            print(
                """
                Migration backfill repaired categories=\(summary.categoriesRepaired), entries=\(summary.entriesRepaired), badgeAwards=\(summary.badgeAwardsRepaired), badgeAwardsDeduped=\(summary.badgeAwardsDeduped), syncEvents=\(summary.syncEventsRepaired), syncEventsDeduped=\(summary.syncEventsDeduped)
                """
            )
        }
#endif
    }
}

enum ModelContainerFactory {
    static func isCloudKitEnabledForCurrentLaunch() -> Bool {
        shouldUseCloudKit()
    }

    static func makeSharedContainer() -> ModelContainer {
        let cloudKitEnabled = shouldUseCloudKit()

        do {
#if DEBUG
            if shouldResetForUITests() {
                _ = removeDefaultStoreArtifacts()
            }
#endif
            return try makeContainer(cloudKitEnabled: cloudKitEnabled)
        } catch {
#if DEBUG
            if recoverFromIncompatibleStore() {
                do {
                    return try makeContainer(cloudKitEnabled: cloudKitEnabled)
                } catch {
                    fatalError("Failed to recreate SwiftData store after recovery: \(error)")
                }
            }
#endif
            if cloudKitEnabled {
                do {
                    print("CloudKit SwiftData container failed to load. Falling back to local-only store. Error: \(error)")
                    return try makeContainer(cloudKitEnabled: false)
                } catch {
                    fatalError("Failed to load SwiftData store with CloudKit and local fallback: \(error)")
                }
            }
            fatalError("Failed to load SwiftData store: \(error)")
        }
    }

    private static func makeContainer(cloudKitEnabled: Bool) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if cloudKitEnabled {
            configuration = ModelConfiguration(cloudKitDatabase: .automatic)
        } else {
            configuration = ModelConfiguration()
        }

        let schema = Schema(versionedSchema: GrindNChillSchemaV2.self)

        return try ModelContainer(
            for: schema,
            migrationPlan: GrindNChillMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func shouldUseCloudKit() -> Bool {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        if processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }

        if processInfo.arguments.contains("-ui-testing-reset-store") ||
            processInfo.arguments.contains("-ui-testing-disable-cloudkit") {
            return false
        }
#endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil {
            return false
        }
        return true
    }

#if DEBUG
    private static func recoverFromIncompatibleStore() -> Bool {
        removeDefaultStoreArtifacts()
    }

    private static func shouldResetForUITests() -> Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-store")
    }

    private static func removeDefaultStoreArtifacts() -> Bool {
        guard let storeURL = defaultStoreURL() else { return false }

        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        var removedAny = false
        let fileManager = FileManager.default

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                removedAny = true
            } catch {
                print("Failed to remove store artifact at \(url): \(error)")
            }
        }

        return removedAny
    }
#endif

    private static func defaultStoreURL() -> URL? {
        do {
            let appSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupportURL.appendingPathComponent("default.store")
        } catch {
            print("Failed to locate Application Support directory: \(error)")
            return nil
        }
    }
}

@MainActor
@Observable
final class SyncMonitor {
    struct EventRecord: Identifiable, Equatable {
        enum EventKind: String {
            case setup = "Setup"
            case importData = "Import"
            case exportData = "Export"
            case unknown = "Sync"
        }

        enum Outcome {
            case inProgress
            case success
            case failure
        }

        let id: UUID
        let kind: EventKind
        let startedAt: Date
        let endedAt: Date?
        let outcome: Outcome
        let detail: String?
    }

    enum Status: Equatable {
        case localOnly
        case syncing
        case upToDate(lastSync: Date?)
        case offlineChanges
        case error
    }

    var status: Status
    var bannerMessage: String?
    var lastImportDate: Date?
    var lastExportDate: Date?

    private let cloudKitEnabled: Bool
    private let modelContext: ModelContext?
    private var cloudKitEventTask: Task<Void, Never>?
    private var eventRecordsByID: [UUID: EventRecord] = [:]
    private var persistedHistoryByEventID: [String: SyncEventHistory] = [:]

    init(cloudKitEnabled: Bool, modelContext: ModelContext? = nil) {
        self.cloudKitEnabled = cloudKitEnabled
        self.modelContext = modelContext
        self.status = cloudKitEnabled ? .syncing : .localOnly

        guard cloudKitEnabled else { return }
        loadPersistedHistory()

        if let lastSyncDate = [lastImportDate, lastExportDate].compactMap({ $0 }).max() {
            status = .upToDate(lastSync: lastSyncDate)
        }

        observeCloudKitEvents()
    }

    var statusTitle: String {
        switch status {
        case .localOnly:
            return "Local only"
        case .syncing:
            return "Syncing"
        case let .upToDate(lastSync):
            guard let lastSync else { return "Up to date" }
            return "Up to date · \(lastSync.formatted(.relative(presentation: .named)))"
        case .offlineChanges:
            return "Offline changes"
        case .error:
            return "Sync issue"
        }
    }

    var statusSymbol: String {
        switch status {
        case .localOnly:
            return "iphone"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.icloud"
        case .offlineChanges:
            return "icloud.slash"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var isStatusWarning: Bool {
        switch status {
        case .offlineChanges, .error:
            return true
        default:
            return false
        }
    }

    func markRefreshRequested() {
        guard cloudKitEnabled else { return }
        status = .syncing
    }

    func markUpToDateIfNeeded() {
        guard cloudKitEnabled else { return }
        status = .upToDate(lastSync: Date.now)
    }

    func clearBanner() {
        bannerMessage = nil
    }

    var recentEvents: [EventRecord] {
        eventRecordsByID.values
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt > rhs.startedAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
    }

    func postMergeReport(_ report: SyncConflictResolverService.MergeReport) {
        guard report.totalResolved > 0 else { return }

        bannerMessage = "Merged \(report.totalResolved) duplicate synced records."
    }

    func postError(_ message: String) {
        status = cloudKitEnabled ? .error : .localOnly
        bannerMessage = message
    }

    private func observeCloudKitEvents() {
        cloudKitEventTask?.cancel()

        cloudKitEventTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            ) {
                guard let self else { return }

                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
                else {
                    continue
                }

                await MainActor.run {
                    self.handleCloudKitEvent(event)
                }
            }
        }
    }

    private func handleCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let kind = mapEventKind(event.type)
        let outcome: EventRecord.Outcome = event.error == nil
            ? (event.endDate == nil ? .inProgress : .success)
            : .failure

        let detail: String?
        if let error = event.error {
            detail = error.localizedDescription
        } else {
            detail = nil
        }

        eventRecordsByID[event.identifier] = EventRecord(
            id: event.identifier,
            kind: kind,
            startedAt: event.startDate,
            endedAt: event.endDate,
            outcome: outcome,
            detail: detail
        )
        trimEventHistoryIfNeeded()
        upsertPersistedHistory(
            id: event.identifier,
            kind: kind,
            startedAt: event.startDate,
            endedAt: event.endDate,
            outcome: outcome,
            detail: detail
        )

        if let error = event.error {
            if isLikelyOfflineError(error) {
                status = .offlineChanges
                bannerMessage = "Cloud sync is offline. Local changes will sync later."
            } else {
                status = .error
                bannerMessage = "Cloud sync failed: \(error.localizedDescription)"
            }
            return
        }

        if event.endDate == nil {
            status = .syncing
            return
        }

        status = .upToDate(lastSync: event.endDate)

        guard let completedAt = event.endDate else { return }
        switch kind {
        case .importData:
            lastImportDate = completedAt
        case .exportData:
            lastExportDate = completedAt
        case .setup, .unknown:
            break
        }
    }

    private func isLikelyOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorNotConnectedToInternet
                || nsError.code == NSURLErrorNetworkConnectionLost
                || nsError.code == NSURLErrorTimedOut
        }

        guard nsError.domain == CKError.errorDomain else { return false }

        switch CKError.Code(rawValue: nsError.code) {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    private func mapEventKind(_ type: NSPersistentCloudKitContainer.EventType) -> EventRecord.EventKind {
        switch type {
        case .setup:
            return .setup
        case .`import`:
            return .importData
        case .export:
            return .exportData
        @unknown default:
            return .unknown
        }
    }

    private func trimEventHistoryIfNeeded(maxCount: Int = 30) {
        guard eventRecordsByID.count > maxCount else { return }

        let overflow = recentEvents.dropFirst(maxCount)
        for record in overflow {
            eventRecordsByID.removeValue(forKey: record.id)
        }
    }

    private func loadPersistedHistory(maxCount: Int = 100) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<SyncEventHistory>(
            sortBy: [
                SortDescriptor(\.startedAt, order: .reverse),
                SortDescriptor(\.recordedAt, order: .reverse)
            ]
        )

        do {
            let persistedHistory = try modelContext.fetch(descriptor)

            for history in persistedHistory {
                persistedHistoryByEventID[history.eventIdentifier] = history

                guard let id = UUID(uuidString: history.eventIdentifier) else { continue }

                let kind = EventRecord.EventKind(rawValue: history.kindRaw) ?? .unknown
                let outcome = EventRecord.Outcome(rawValue: history.outcomeRaw) ?? .inProgress

                eventRecordsByID[id] = EventRecord(
                    id: id,
                    kind: kind,
                    startedAt: history.startedAt,
                    endedAt: history.endedAt,
                    outcome: outcome,
                    detail: history.detail
                )

                guard history.endedAt != nil, outcome == .success else { continue }

                switch kind {
                case .importData:
                    if lastImportDate == nil || (history.endedAt ?? .distantPast) > (lastImportDate ?? .distantPast) {
                        lastImportDate = history.endedAt
                    }
                case .exportData:
                    if lastExportDate == nil || (history.endedAt ?? .distantPast) > (lastExportDate ?? .distantPast) {
                        lastExportDate = history.endedAt
                    }
                case .setup, .unknown:
                    break
                }
            }

            trimPersistedHistoryIfNeeded(maxCount: maxCount)
            trimEventHistoryIfNeeded()
        } catch {
            print("Failed to load persisted sync history: \(error)")
        }
    }

    private func upsertPersistedHistory(
        id: UUID,
        kind: EventRecord.EventKind,
        startedAt: Date,
        endedAt: Date?,
        outcome: EventRecord.Outcome,
        detail: String?
    ) {
        guard let modelContext else { return }

        let eventIdentifier = id.uuidString
        let history: SyncEventHistory
        if let existing = persistedHistoryByEventID[eventIdentifier] {
            history = existing
        } else {
            history = SyncEventHistory(
                eventIdentifier: eventIdentifier,
                kindRaw: kind.rawValue,
                outcomeRaw: outcome.rawValue,
                startedAt: startedAt
            )
            modelContext.insert(history)
            persistedHistoryByEventID[eventIdentifier] = history
        }

        history.kindRaw = kind.rawValue
        history.outcomeRaw = outcome.rawValue
        history.startedAt = startedAt
        history.endedAt = endedAt
        history.detail = detail
        history.recordedAt = Date.now

        do {
            try modelContext.save()
            trimPersistedHistoryIfNeeded()
        } catch {
            print("Failed to persist sync history event: \(error)")
        }
    }

    private func trimPersistedHistoryIfNeeded(maxCount: Int = 100) {
        guard let modelContext else { return }
        guard persistedHistoryByEventID.count > maxCount else { return }

        let sortedHistory = persistedHistoryByEventID.values.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            if lhs.recordedAt != rhs.recordedAt {
                return lhs.recordedAt > rhs.recordedAt
            }
            return lhs.eventIdentifier > rhs.eventIdentifier
        }

        let overflow = sortedHistory.dropFirst(maxCount)
        for history in overflow {
            persistedHistoryByEventID.removeValue(forKey: history.eventIdentifier)
            if let id = UUID(uuidString: history.eventIdentifier) {
                eventRecordsByID.removeValue(forKey: id)
            }
            modelContext.delete(history)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to trim persisted sync history: \(error)")
        }
    }
}

private extension SyncMonitor.EventRecord.Outcome {
    init?(rawValue: String) {
        switch rawValue {
        case "inProgress":
            self = .inProgress
        case "success":
            self = .success
        case "failure":
            self = .failure
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .inProgress:
            return "inProgress"
        case .success:
            return "success"
        case .failure:
            return "failure"
        }
    }
}
