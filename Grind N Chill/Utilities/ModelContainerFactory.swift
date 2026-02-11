import Foundation
import Observation
import CoreData
import CloudKit
import SwiftData

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
        let schema = Schema([Category.self, Entry.self, BadgeAward.self, SyncEventHistory.self])
        let configuration: ModelConfiguration

        if cloudKitEnabled {
            configuration = ModelConfiguration(cloudKitDatabase: .automatic)
        } else {
            configuration = ModelConfiguration()
        }

        return try ModelContainer(for: schema, configurations: [configuration])
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
