import Foundation
import SwiftData

@Model
final class BadgeAward {
    var awardKey: String = ""
    var dateAwarded: Date = Date.now

    init(awardKey: String, dateAwarded: Date = Date.now) {
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
    var recordedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        eventIdentifier: String,
        kindRaw: String,
        outcomeRaw: String,
        startedAt: Date,
        endedAt: Date? = nil,
        detail: String? = nil,
        recordedAt: Date = Date.now
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.kindRaw = kindRaw
        self.outcomeRaw = outcomeRaw
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.detail = detail
        self.recordedAt = recordedAt
    }
}
