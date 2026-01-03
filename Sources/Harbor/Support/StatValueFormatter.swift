import Foundation

enum StatValueFormatter {
    static func compact(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 10000 {
            let short = self.oneDecimal(value, divisor: 1000)
            return "\(short)K"
        }
        if value < 1_000_000 {
            return "\(value / 1000)K"
        }
        if value < 10_000_000 {
            let short = self.oneDecimal(value, divisor: 1_000_000)
            return "\(short)M"
        }
        if value >= 1_000_000_000 {
            return "999M"
        }
        return "\(value / 1_000_000)M"
    }

    private static func oneDecimal(_ value: Int, divisor: Double) -> String {
        let scaled = Double(value) / divisor
        let formatted = String(format: "%.1f", scaled)
        if formatted.hasSuffix(".0") {
            return String(formatted.dropLast(2))
        }
        if formatted.hasPrefix("10") {
            return "10"
        }
        return formatted
    }
}
