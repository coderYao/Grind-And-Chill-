import Foundation

enum AppStorageKeys {
    static let usdPerHour = "settings.usdPerHour"
    static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    static let activeCategoryID = "session.activeCategoryID"
    static let activeStartTime = "session.activeStartTime"
    static let activeElapsedSeconds = "session.activeElapsedSeconds"
    static let activeIsPaused = "session.activeIsPaused"
    static let activeRunningSegmentStartTime = "session.activeRunningSegmentStartTime"
    static let lastImportUndoPayload = "history.lastImportUndoPayload"
    static let lastCategoryDeleteUndoPayload = "categories.lastDeleteUndoPayload"
    static let lastHistoryDeleteUndoPayload = "history.lastDeleteUndoPayload"
}
