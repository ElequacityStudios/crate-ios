import Foundation

/// The device's pairing file, which Built-in StikJIT needs to reach the
/// iPhone's own debug services through LocalDevVPN. It's made on a computer
/// (idevice_pair, iloader) or by StikDebug, and is a credential: crate keeps it
/// in Documents/StikJIT/pairingFile.plist, the place StikJIT's integration
/// guide names, so idevice_pair and Finder can put it there too, and never logs it.
enum PairingFile {
    static let url = URL.documentsDirectory
        .appendingPathComponent("StikJIT", isDirectory: true)
        .appendingPathComponent("pairingFile.plist")

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func read() -> Data? {
        try? Data(contentsOf: url)
    }

    enum ImportError: LocalizedError {
        case unreadable
        case notAPairingFile

        var errorDescription: String? {
            switch self {
            case .unreadable: "crate couldn't read that file."
            case .notAPairingFile: "That isn't a pairing file. It should be a property list, usually named pairingFile.plist or ending in .mobiledevicepairing."
            }
        }
    }

    /// Keeps a pairing record made on this iPhone (OnDevicePairing).
    static func store(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        JITLog.write("jit: paired this iPhone (\(data.count)-byte record)")
    }

    /// Deletes crate's copy. iOS keeps its side of a pairing made on this
    /// iPhone (it lists none for crate to remove), but without this copy crate
    /// can't use it.
    static func forget() {
        try? FileManager.default.removeItem(at: url)
        JITLog.write("jit: forgot the pairing")
    }

    /// Copies a file the person picked in Files over the stored one.
    static func importFile(from source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source) else { throw ImportError.unreadable }
        guard (try? PropertyListSerialization.propertyList(from: data, format: nil)) is [String: Any] else {
            throw ImportError.notAPairingFile
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        JITLog.write("jit: imported a pairing file (\(data.count) bytes)")
    }
}
