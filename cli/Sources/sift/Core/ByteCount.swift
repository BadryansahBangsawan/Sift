import Foundation

enum ByteCount {
    /// File and volume sizes, in the decimal units macOS shows (1000-based).
    static func human(_ bytes: Int64) -> String {
        format(bytes, base: 1000)
    }

    /// Memory is a binary quantity: a 16 GB Mac reports 17,179,869,184 bytes,
    /// so RAM is rendered with 1024-based units and GB labels the way macOS and
    /// the app's Performance screen show it. File sizes stay decimal above.
    static func memory(_ bytes: Int64) -> String {
        format(bytes, base: 1024)
    }

    private static func format(_ bytes: Int64, base: Double) -> String {
        // The app formats an empty size as "0 KB" (ByteCountFormatter with
        // allowsNonnumericFormatting off), so the CLI says the same thing.
        if bytes <= 0 { return "0 KB" }
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var idx = 0
        while value >= base && idx < units.count - 1 {
            value /= base
            idx += 1
        }
        if idx == 0 {
            return value == 1 ? "1 byte" : "\(Int(value)) bytes"
        }

        // Rounding to one decimal place can turn 999.96 into 1000.0; promote to
        // the next unit rather than print a thousand of a smaller one.
        value = (value * 10).rounded() / 10
        if value >= 1000, idx < units.count - 1 {
            value /= base
            value = (value * 10).rounded() / 10
            idx += 1
        }

        var formatted = String(format: "%.1f", value)
        if formatted.hasSuffix(".0") { formatted = String(formatted.dropLast(2)) }
        return "\(formatted) \(units[idx])"
    }
}
