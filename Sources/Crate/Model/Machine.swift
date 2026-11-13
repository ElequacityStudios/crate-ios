import Foundation

/// One installed VM: a distribution at a version, and the hardware it is given.
struct Machine: Identifiable, Codable, Hashable {
    var id = UUID()
    var distributionID: String
    var version: String
    var codename: String?
    var cpuCount: Int
    var memoryGB: Int
    var diskGB: Int
    var diskUsedGB: Double
    var desktop: String
    var display: String
    var architecture = "arm64"
    /// An asset name. Nil until the VM has run once and there is something to show.
    var screenshot: String?
    var lastStarted: Date?

    var distribution: Distribution { .named(distributionID) }
    var name: String { distribution.name }

    /// "13.2" or "13.2 Trixie".
    var versionLabel: String {
        [version, codename].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Sample data

// SAMPLE DATA: stands in for VMs on disk until installs are real.
extension Machine {
    static let sampleDebian = Machine(
        distributionID: "debian", version: "13.2", codename: "Trixie",
        cpuCount: 4, memoryGB: 6, diskGB: 32, diskUsedGB: 7.4,
        desktop: "Xfce", display: "1280 × 800", screenshot: "debian-xfce",
        lastStarted: Date(timeIntervalSinceNow: -3 * 3600))

    static let sampleArch = Machine(
        distributionID: "arch", version: "2026.11.01",
        cpuCount: 4, memoryGB: 4, diskGB: 32, diskUsedGB: 9.1,
        desktop: "Hyprland", display: "1280 × 800", screenshot: "arch-hyprland",
        lastStarted: Date(timeIntervalSinceNow: -2 * 86400))

    static let samples = [sampleDebian, sampleArch]
}
