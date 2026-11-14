// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// What crate did this launch: JIT, pairing, and the engine's own lines, kept in
/// `Library/Caches/crate.log` (a phone's unified log can't be read from a Mac, a
/// file can) and shared by Settings > Export Logs.
enum AppLog {
    static let url = URL.cachesDirectory.appendingPathComponent("crate.log")
    private static let lock = NSLock()
    private static let started = Date.now

    /// Starts this launch's log afresh.
    static func begin() {
        lock.withLock {
            try? Data().write(to: url)
        }
        write("crate launched, iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    static func write(_ line: String) {
        let stamp = String(format: "[%7.3f] ", Date.now.timeIntervalSince(started))
        lock.withLock {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((stamp + line + "\n").utf8))
        }
    }

    static func contents() -> String {
        lock.withLock { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }
}
