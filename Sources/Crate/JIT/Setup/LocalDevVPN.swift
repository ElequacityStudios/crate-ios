import Network
import UIKit

/// LocalDevVPN, the free App Store app whose loopback tunnel makes this
/// iPhone's own debug services reachable from an app on it. Built-in StikJIT
/// connects through it, to 10.7.0.1 port 49152 by default.
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

    /// Whether the tunnel works: a connection to the address StikJIT will use,
    /// which says more than looking for its network interface.
    static func probe(timeout: TimeInterval = 1.5) async -> Tunnel {
        let connection = NWConnection(host: "10.7.0.1", port: 49152, using: .tcp)
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
                    if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        answer(.localNetworkDenied)
                    } else if case .failed = state {
                        answer(.down)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { answer(.down) }
        }
    }
}
