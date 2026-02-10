import Foundation
import SwiftData

@Model
final class BadgeAward {
    @Attribute(.unique) var awardKey: String
    var dateAwarded: Date

    init(awardKey: String, dateAwarded: Date = .now) {
        self.awardKey = awardKey
        self.dateAwarded = dateAwarded
    }
}
