import Foundation

enum Format {
    /// "5.8 GB", "107 GB", "384 MB". Decimal units, as the Settings app uses,
    /// with one decimal only where it says something.
    static func bytes(_ count: Int64) -> String {
        let gb = Double(count) / 1e9
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return "\(gb.formatted(.number.precision(.fractionLength(1)))) GB" }
        return "\(Int((Double(count) / 1e6).rounded())) MB"
    }

    /// Memory in the binary units it's sold in: an "8 GB" iPhone has 8 GiB, and
    /// a VM given "4 GB" gets 4 GiB.
    static func memory(_ count: UInt64) -> String {
        let gib = Double(count) / 1_073_741_824
        if gib >= 1 { return "\(gib.formatted(.number.precision(.fractionLength(0...1)))) GB" }
        return "\(Int((Double(count) / 1_048_576).rounded())) MB"
    }

    /// "1 hour ago". Nil reads as "Never".
    static func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    /// Free space on the volume that holds the app's data.
    static func freeDiskBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
