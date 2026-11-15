// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import dnssd
import Foundation

/// The ports the iPhone's Remote Pairing service may be listening on, as
/// Bonjour has them (`_remotepairing._tcp`). StikJIT connects to that service
/// through LocalDevVPN's tunnel. It's usually on 49152, but iOS picks the port,
/// so it's looked up rather than assumed. crate does the looking, in front with
/// Local Network access, since its helper extension may not get answers.
///
/// Other iPhones and iPads on the same network may advertise the service too,
/// so this only gathers candidates: which one is this iPhone's is for the
/// tunnel to say (LocalDevVPN.check), since 10.7.0.1 reaches only this one,
/// and they're tried only when the usual port doesn't answer.
enum RemotePairingPort {
    /// Where the service usually is, and StikJIT's own guess.
    static let usual: UInt16 = 49152

    /// The ports found within `timeout`, those advertised on the loopback
    /// interface (this iPhone's own) first. Empty if nothing answered: Local
    /// Network access off, or no Bonjour at all.
    static func lookUp(timeout: TimeInterval = 1.5) async -> [UInt16] {
        await withCheckedContinuation { continuation in
            Lookup(timeout: timeout) { continuation.resume(returning: $0) }.start()
        }
    }

    /// One lookup: a browse for the service, and a resolve of each instance
    /// found, all on one queue, until the time is up.
    private final class Lookup: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.amendez.crate.remote-pairing-port")
        private let timeout: TimeInterval
        private let done: ([UInt16]) -> Void
        private var browse: DNSServiceRef?
        private var resolves: [DNSServiceRef] = []
        /// Port, and whether it was on the loopback interface. On `queue`.
        private var found: [(port: UInt16, local: Bool)] = []
        private var finished = false
        private let loopback = if_nametoindex("lo0")

        init(timeout: TimeInterval, done: @escaping ([UInt16]) -> Void) {
            self.timeout = timeout
            self.done = done
        }

        /// Keeps itself alive until it finishes: the callbacks' context is an
        /// unretained pointer to it.
        func start() {
            let context = Unmanaged.passRetained(self).toOpaque()
            queue.async {
                var ref: DNSServiceRef?
                let error = DNSServiceBrowse(&ref, 0, 0, "_remotepairing._tcp", nil, Lookup.browsed, context)
                if error == kDNSServiceErr_NoError, let ref {
                    self.browse = ref
                    DNSServiceSetDispatchQueue(ref, self.queue)
                } else {
                    self.finish()
                    return
                }
                self.queue.asyncAfter(deadline: .now() + self.timeout) { self.finish() }
            }
        }

        private static let browsed: DNSServiceBrowseReply = { _, flags, interface, error, name, type, domain, context in
            guard let context, error == kDNSServiceErr_NoError,
                  flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0 else { return }
            let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
            guard !lookup.finished else { return }
            var ref: DNSServiceRef?
            if DNSServiceResolve(&ref, 0, interface, name, type, domain, Lookup.resolved, context) == kDNSServiceErr_NoError,
               let ref {
                lookup.resolves.append(ref)
                DNSServiceSetDispatchQueue(ref, lookup.queue)
            }
        }

        private static let resolved: DNSServiceResolveReply = { _, _, interface, error, _, _, port, _, _, context in
            guard let context, error == kDNSServiceErr_NoError else { return }
            let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
            guard !lookup.finished else { return }
            // In network byte order.
            lookup.found.append((UInt16(bigEndian: port), interface == lookup.loopback))
        }

        /// On `queue`. Stops everything and answers, once.
        private func finish() {
            guard !finished else { return }
            finished = true
            for ref in resolves { DNSServiceRefDeallocate(ref) }
            resolves.removeAll()
            if let browse { DNSServiceRefDeallocate(browse) }
            browse = nil
            var ports: [UInt16] = []
            for candidate in found.filter(\.local) + found.filter({ !$0.local }) where !ports.contains(candidate.port) {
                ports.append(candidate.port)
            }
            done(ports)
            Unmanaged.passUnretained(self).release()
        }
    }
}
