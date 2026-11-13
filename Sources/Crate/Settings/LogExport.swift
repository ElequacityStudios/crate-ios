import Foundation

/// The file Settings > Logs shares.
enum LogExport {
    /// STUB: writes a sample log, since nothing logs yet, and returns where it is.
    /// The real one will gather the engine's and the app's logs into one file.
    static func prepare() -> URL {
        let stamp = Date.now.formatted(
            Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("crate-\(stamp).log")
        let memory = MemoryReport()
        let lines = [
            "Crate \(appVersion) -- sample log (no engine wired in yet)",
            "date: \(Date.now.formatted(.iso8601))",
            "device: \(deviceModel), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "memory: physical \(Format.memory(memory.physical)), "
                + "available \(memory.available.map(Format.memory) ?? "n/a"), "
                + "footprint \(Format.memory(memory.footprint))",
            "jit: stub=\(UserDefaults.standard.bool(forKey: SettingsKey.stubJITEnabled))",
            "[0.000] app init",
            "[0.012] jit: method=\(UserDefaults.standard.string(forKey: SettingsKey.jitMethod) ?? JITMethod.standard.rawValue)",
            "[0.013] engine: not wired in",
        ]
        try? lines.joined(separator: "\n").appending("\n")
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
