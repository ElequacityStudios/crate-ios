// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Network
import UIKit

/// LocalDevVPN, the free App Store app whose loopback tunnel makes this
/// iPhone's own debug services reachable from an app on it. Built-in StikJIT
/// connects through it, to 10.7.0.1 and the Remote Pairing service's port:
/// usually 49152, but looked up (RemotePairingPort) and passed to the helper.
///
/// It opens on `localdevvpn://enable?scheme=X`, connects, and comes back to
/// `X://`, which is crate's own URL scheme.
enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!
    static let connectURL = URL(string: "localdevvpn://enable?scheme=crate")!

    /// Needs `localdevvpn` in LSApplicationQueriesSchemes, or iOS always says no.
    @MainActor
    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "localdevvpn://")!)
    }

    enum Tunnel: Equatable {
        case up
        /// iOS refused the connection: Local Network access is off for crate.
        case localNetworkDenied
        case down
    }

    /// What a check found: whether the tunnel works, and if it does, the port
    /// the Remote Pairing service answered on.
    struct Check: Equatable {
        var tunnel: Tunnel
        var port: UInt16?

        /// The port for the helper to use instead of looking for one itself:
        /// only one found by looking, when the usual one didn't answer. When
        /// the usual one did, StikJIT's own search and fallback stay as they
        /// were.
        var portForHelper: UInt16? {
            guard tunnel == .up, let port, port != RemotePairingPort.usual else { return nil }
            return port
        }
    }

    /// Whether the tunnel works, and on which port: a connection through it,
    /// which says more than looking for its network interface, to the usual
    /// port, and only if that doesn't answer, to those Bonjour says the
    /// service is on (RemotePairingPort). Only this iPhone answers on 10.7.0.1.
    ///
    /// With `waitingUpTo`, a tunnel that isn't up yet is checked again every
    /// second until then: LocalDevVPN may still be connecting, or crate may
    /// have only just come back from it. The result goes in the log.
    @MainActor
    static func check(waitingUpTo wait: Duration = .zero) async -> Check {
        let clock = ContinuousClock()
        let deadline = clock.now + wait
        var looked: [UInt16]?
        var result = Check(tunnel: .down)
        while true {
            // The lookup starts at once but is only waited for if the usual
            // port doesn't answer.
            let lookup = looked.map { found in Task { found } } ?? Task { await RemotePairingPort.lookUp() }
            let usual = await probe(port: RemotePairingPort.usual)
            if usual == .up {
                result = Check(tunnel: .up, port: RemotePairingPort.usual)
            } else {
                let found = await lookup.value
                looked = found.isEmpty ? nil : found
                result = await firstAnswering(found.filter { $0 != RemotePairingPort.usual })
                if result.tunnel == .down, usual == .localNetworkDenied { result.tunnel = .localNetworkDenied }
            }
            if result.tunnel == .up || clock.now >= deadline { break }
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
        }
        let bonjour = looked.map { $0.map(String.init).joined(separator: ", ") } ?? "not needed or none"
        switch result.tunnel {
        case .up: AppLog.write("jit: LocalDevVPN is connected, Remote Pairing on port \(result.port ?? 0) (Bonjour: \(bonjour))")
        case .localNetworkDenied: AppLog.write("jit: LocalDevVPN: Local Network access is off for crate")
        case .down: AppLog.write("jit: LocalDevVPN isn't connected: nothing answered on 10.7.0.1 (Bonjour: \(bonjour))")
        }
        return result
    }

    /// Tries every port at once and answers with the earliest in `ports` that
    /// connected, or, with none, Local Network denied if any said so.
    private static func firstAnswering(_ ports: [UInt16]) async -> Check {
        guard !ports.isEmpty else { return Check(tunnel: .down) }
        let results = await withTaskGroup(of: (Int, Tunnel).self) { group in
            for (index, port) in ports.enumerated() {
                group.addTask { (index, await probe(port: port)) }
            }
            var results = [Tunnel](repeating: .down, count: ports.count)
            for await (index, tunnel) in group { results[index] = tunnel }
            return results
        }
        if let index = results.firstIndex(of: .up) { return Check(tunnel: .up, port: ports[index]) }
        return Check(tunnel: results.contains(.localNetworkDenied) ? .localNetworkDenied : .down)
    }

    /// Whether a connection through the tunnel to `port` works.
    static func probe(port: UInt16 = RemotePairingPort.usual, timeout: TimeInterval = 1.5) async -> Tunnel {
        let connection = NWConnection(host: "10.7.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "com.amendez.crate.tunnel-probe")
        return await withCheckedContinuation { continuation in
            // Everything below runs on `queue`, so answering once needs no lock.
            final class Once: @unchecked Sendable { var answered = false }
            let once = Once()
            let answer: @Sendable (Tunnel) -> Void = { tunnel in
                guard !once.answered else { return }
                once.answered = true
                connection.cancel()
                continuation.resume(returning: tunnel)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    answer(.up)
                case .waiting, .failed:
                    // Waiting is a refused connection or no route yet: down for
                    // now (check tries again), not worth the rest of the timeout.
                    answer(connection.currentPath?.unsatisfiedReason == .localNetworkDenied ? .localNetworkDenied : .down)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { answer(.down) }
        }
    }
}
