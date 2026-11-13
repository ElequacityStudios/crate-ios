import Foundation

/// The file Settings > Logs shares.
enum LogExport {
    /// Writes this launch's log, after a few lines about the device, and returns
    /// where it is. Only JIT logs so far; the engine's lines join it once it's in.
    static func prepare() -> URL {
        let stamp = Date.now.formatted(
            Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crate-\(stamp).log")
        let memory = MemoryReport()
        let lines = [
            "crate \(appVersion)",
            "date: \(Date.now.formatted(.iso8601))",
            "device: \(deviceModel), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "memory: physical \(Format.memory(memory.physical)), "
                + "available \(memory.available.map { Format.memory($0) } ?? "n/a"), "
                + "footprint \(Format.memory(memory.footprint))",
            "jit method: \(UserDefaults.standard.string(forKey: SettingsKey.jitMethod) ?? JITMethod.standard.rawValue)",
            "",
        ]
        try? (lines.joined(separator: "\n") + "\n" + AppLog.contents())
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
