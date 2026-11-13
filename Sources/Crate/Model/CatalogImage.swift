import Foundation

/// A system image Crate can download and install.
struct CatalogImage: Identifiable, Hashable {
    var id: String { distributionID }
    let distributionID: String
    let version: String
    let codename: String?
    let desktop: String
    let downloadBytes: Int64
    /// Disk space the installed VM takes before the guest writes anything.
    let installedBytes: Int64

    var distribution: Distribution { .named(distributionID) }
    var name: String { distribution.name }

    /// The VM this image becomes once installed with `memoryGB` of RAM.
    func machine(memoryGB: Int) -> Machine {
        Machine(distributionID: distributionID, version: version, codename: codename,
                cpuCount: 4, memoryGB: memoryGB, diskGB: 32,
                diskUsedGB: Double(installedBytes) / 1e9,
                desktop: desktop, display: "1280 × 800")
    }
}

// SAMPLE DATA: these versions and sizes are made up for the UI. The real list
// will come from wherever Crate publishes its images.
extension CatalogImage {
    static let catalog: [CatalogImage] = [
        CatalogImage(distributionID: "debian", version: "13.2", codename: "Trixie",
                     desktop: "Xfce", downloadBytes: 1_480_000_000,
                     installedBytes: 4_300_000_000),
        CatalogImage(distributionID: "arch", version: "2026.11.01", codename: nil,
                     desktop: "Hyprland", downloadBytes: 1_920_000_000,
                     installedBytes: 5_600_000_000),
    ]
}
