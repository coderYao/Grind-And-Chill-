import Foundation
import Observation

struct CompletedSession {
    let categoryID: UUID
    let startedAt: Date
    let endedAt: Date

    var elapsedSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

@MainActor
@Observable
final class TimerManager {
    private let userDefaults: UserDefaults

    var activeCategoryID: UUID?
    var startTime: Date?

    var isRunning: Bool {
        activeCategoryID != nil && startTime != nil
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        restoreSessionIfNeeded()
    }

    func start(categoryID: UUID, at date: Date = .now) {
        activeCategoryID = categoryID
        startTime = date
        persistSession()
    }

    func stop(at date: Date = .now) -> CompletedSession? {
        guard
            let activeCategoryID,
            let startTime
        else {
            clearSession()
            return nil
        }

        let completed = CompletedSession(
            categoryID: activeCategoryID,
            startedAt: startTime,
            endedAt: date
        )

        clearSession()
        return completed
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard let startTime else { return 0 }
        return max(0, Int(date.timeIntervalSince(startTime)))
    }

    func clearSession() {
        activeCategoryID = nil
        startTime = nil
        userDefaults.removeObject(forKey: AppStorageKeys.activeCategoryID)
        userDefaults.removeObject(forKey: AppStorageKeys.activeStartTime)
    }

    func restoreSessionIfNeeded() {
        guard
            let categoryIDString = userDefaults.string(forKey: AppStorageKeys.activeCategoryID),
            let categoryID = UUID(uuidString: categoryIDString),
            let startTime = userDefaults.object(forKey: AppStorageKeys.activeStartTime) as? Date
        else {
            clearSession()
            return
        }

        activeCategoryID = categoryID
        self.startTime = startTime
    }

    private func persistSession() {
        guard
            let activeCategoryID,
            let startTime
        else {
            return
        }

        userDefaults.set(activeCategoryID.uuidString, forKey: AppStorageKeys.activeCategoryID)
        userDefaults.set(startTime, forKey: AppStorageKeys.activeStartTime)
    }
}
