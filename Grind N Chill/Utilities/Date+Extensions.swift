import Foundation

extension Date {
    func isoDayString(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
