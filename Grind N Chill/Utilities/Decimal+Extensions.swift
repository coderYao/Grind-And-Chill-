import Foundation

extension Decimal {
    static let zeroValue = Decimal(0)

    func rounded(scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, mode)
        return output
    }
}
