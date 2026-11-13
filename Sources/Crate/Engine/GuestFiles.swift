import Foundation

/// Where a VM's guest lives: the kernel, its initial ramdisk, and the disk, in
/// `Library/Application Support/VMs/<name>/`.
///
/// STUB naming: until installs are real, a VM's folder is named for its
/// distribution ("debian"), and the files get there from a Mac with devicectl.
/// Real installs will give each VM a folder of its own.
struct GuestFiles {
    let directory: URL

    init(for machine: Machine) {
        directory = URL.applicationSupportDirectory
            .appendingPathComponent("VMs", isDirectory: true)
            .appendingPathComponent(machine.distributionID, isDirectory: true)
    }

    var kernel: URL { directory.appendingPathComponent("vmlinuz") }
    var initrd: URL { directory.appendingPathComponent("initrd.img") }
    var disk: URL { directory.appendingPathComponent("disk.img") }

    /// The files a boot needs that aren't there, by name.
    var missing: [String] {
        [kernel, initrd, disk]
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)
    }
}
