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
