import Foundation

/// Where a VM's guest lives: the kernel, its initial ramdisk, and the disk, in
/// `Library/Application Support/VMs/<the VM's ID>/`.
struct GuestFiles {
    /// Every VM's folder.
    static let root = URL.applicationSupportDirectory.appendingPathComponent("VMs", isDirectory: true)

    let directory: URL

    init(for machine: Machine) {
        directory = Self.root.appendingPathComponent(machine.id.uuidString, isDirectory: true)
    }

    var kernel: URL { directory.appendingPathComponent("vmlinuz") }
    var initrd: URL { directory.appendingPathComponent("initrd.img") }
    var disk: URL { directory.appendingPathComponent("disk.img") }
    /// The owner's first-boot settings (SeedDisk), attached read-only beside
    /// the disk; absent for a VM put on the iPhone by hand.
    var seed: URL { directory.appendingPathComponent("seed.img") }
    /// Its screen as it was when last stopped, for its card on Home.
    var preview: URL { directory.appendingPathComponent("preview.jpg") }

    /// The files a boot needs that aren't there, by name.
    var missing: [String] {
        [kernel, initrd, disk]
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)
    }

    /// Deletes the VM's folder and everything in it.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Deletes every VM's files.
    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
