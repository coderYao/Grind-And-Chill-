import Foundation
import Observation

struct CompletedSession {
    let categoryID: UUID
    let startedAt: Date
    let endedAt: Date
    let elapsedSeconds: Int
}

@MainActor
@Observable
final class TimerManager {
    private let userDefaults: UserDefaults

    var activeCategoryID: UUID?
    var startTime: Date?
    var isPaused: Bool = false

    private var runningSegmentStartTime: Date?
    private var accumulatedElapsedSeconds: Int = 0

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
        isPaused = false
        runningSegmentStartTime = date
        accumulatedElapsedSeconds = 0
        persistSession()
    }

    @discardableResult
    func pause(at date: Date = .now) -> Bool {
        guard isRunning, isPaused == false else { return false }
        accumulatedElapsedSeconds = totalElapsedSeconds(at: date)
        runningSegmentStartTime = nil
        isPaused = true
        persistSession()
        return true
    }

    @discardableResult
    func resume(at date: Date = .now) -> Bool {
        guard isRunning, isPaused else { return false }
        runningSegmentStartTime = date
        isPaused = false
        persistSession()
        return true
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
            endedAt: date,
            elapsedSeconds: totalElapsedSeconds(at: date)
        )

        clearSession()
        return completed
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard isRunning else { return 0 }
        return totalElapsedSeconds(at: date)
    }

    func clearSession() {
        activeCategoryID = nil
        startTime = nil
        isPaused = false
        runningSegmentStartTime = nil
        accumulatedElapsedSeconds = 0
        userDefaults.removeObject(forKey: AppStorageKeys.activeCategoryID)
        userDefaults.removeObject(forKey: AppStorageKeys.activeStartTime)
        userDefaults.removeObject(forKey: AppStorageKeys.activeElapsedSeconds)
        userDefaults.removeObject(forKey: AppStorageKeys.activeIsPaused)
        userDefaults.removeObject(forKey: AppStorageKeys.activeRunningSegmentStartTime)
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
        accumulatedElapsedSeconds = userDefaults.integer(forKey: AppStorageKeys.activeElapsedSeconds)
        isPaused = userDefaults.bool(forKey: AppStorageKeys.activeIsPaused)
        if let runningStart = userDefaults.object(
            forKey: AppStorageKeys.activeRunningSegmentStartTime
        ) as? Date {
            runningSegmentStartTime = runningStart
        } else {
            runningSegmentStartTime = isPaused ? nil : startTime
        }
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
        userDefaults.set(accumulatedElapsedSeconds, forKey: AppStorageKeys.activeElapsedSeconds)
        userDefaults.set(isPaused, forKey: AppStorageKeys.activeIsPaused)
        if let runningSegmentStartTime {
            userDefaults.set(
                runningSegmentStartTime,
                forKey: AppStorageKeys.activeRunningSegmentStartTime
            )
        } else {
            userDefaults.removeObject(forKey: AppStorageKeys.activeRunningSegmentStartTime)
        }
    }

    private func totalElapsedSeconds(at date: Date) -> Int {
        let segmentElapsed: Int
        if isPaused {
            segmentElapsed = 0
        } else if let runningSegmentStartTime {
            segmentElapsed = max(0, Int(date.timeIntervalSince(runningSegmentStartTime)))
        } else if let startTime {
            segmentElapsed = max(0, Int(date.timeIntervalSince(startTime)))
        } else {
            segmentElapsed = 0
        }

        return max(0, accumulatedElapsedSeconds + segmentElapsed)
    }
}
