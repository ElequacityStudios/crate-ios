import Foundation
#if canImport(StikJIT)
import StikJIT
#endif

/// The built-in JIT enabler: a second process that attaches a debugger to
/// crate. crate can't do it itself, because attaching stops every thread of the
/// process being attached to, the one talking to the debugger included.
///
/// A classic app extension on Apple's AR viewer point with a FALSEPREDICATE
/// activation rule, so nothing but crate ever starts it: crate begins a request
/// with NSExtension's private calls (HelperLauncher.m). One request, one reply,
/// each the item's userInfo:
///
///   in:  "op": "enable" (the default) or "prepare"; "pairing", the pairing
///        file's bytes; for enable, "pid", the process to attach to
///   out: "ok", "summary", and "log", this helper's lines (there's no channel to
///        stream them back on)
///
/// "prepare" only readies the device (reaches it through the tunnel, mounts
/// the developer disk image), for the setup sheet; "enable" does that too.
///
/// StikJIT (MPL-2.0, Frameworks/StikJIT.xcframework, device builds only) does
/// the work: through LocalDevVPN's tunnel it mounts the developer disk image
/// when needed, attaches, and runs legacy.js, which authorizes the region crate
/// asks for with `brk #0x69` and detaches. So the reply comes once crate has
/// its code region, or with what went wrong.
@objc(CrateJITHelper)
final class CrateJITHelper: NSObject, NSExtensionRequestHandling {
    /// StikJIT's calls block and must run in order, one at a time.
    private static let queue = DispatchQueue(label: "com.amendez.crate.jithelper")

    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo ?? [:]
        Self.queue.async {
            var lines: [String] = []
            var reply: [String: Any] = [:]
            do {
                let log: (String) -> Void = { lines.append($0) }
                switch request["op"] as? String ?? "enable" {
                case "prepare": reply["summary"] = try Self.prepare(request, log: log)
                default: reply["summary"] = try Self.enable(request, log: log)
                }
                reply["ok"] = true
            } catch {
                reply["ok"] = false
                reply["summary"] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            reply["log"] = lines
            let item = NSExtensionItem()
            item.userInfo = reply
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }

    private static func enable(_ request: [AnyHashable: Any], log: @escaping (String) -> Void) throws -> String {
        guard let pid = request["pid"] as? Int, pid > 0 else { throw HelperError("no pid to attach to") }
        #if canImport(StikJIT)
        return try withPairingFile(request) { pairingURL in
            let started = Date.now
            log("attaching to \(pid)")
            try StikJIT.enableJIT(
                targetPID: Int32(pid),
                pairingFile: pairingURL,
                ddiPaths: ddiPaths,
                script: .legacy,
                preparationProgress: { stage in log("prepare: \(stage)") },
                progress: { line in log(line) })
            return String(format: "attached, authorized and detached in %.1f s", Date.now.timeIntervalSince(started))
        }
        #else
        throw HelperError("this helper was built without StikJIT (Simulator builds have none)")
        #endif
    }

    private static func prepare(_ request: [AnyHashable: Any], log: @escaping (String) -> Void) throws -> String {
        #if canImport(StikJIT)
        return try withPairingFile(request) { pairingURL in
            let readiness = StikJIT.prepareDevice(pairingFile: pairingURL, paths: ddiPaths) { stage in
                log("prepare: \(stage)")
            }
            switch readiness {
            case .ready(let security):
                let txm = security.isTXMPresent.map { $0 ? "TXM present" : "no TXM" } ?? "TXM unknown"
                return "ready, \(txm)"
            case .unreachable(let reason):
                throw HelperError("couldn't reach this iPhone through LocalDevVPN: \(reason)")
            case .preparationFailed(let reason):
                throw HelperError(reason)
            @unknown default:
                throw HelperError("StikJIT gave an answer this helper doesn't know")
            }
        }
        #else
        throw HelperError("this helper was built without StikJIT (Simulator builds have none)")
        #endif
    }

    #if canImport(StikJIT)
    /// The developer disk image, downloaded once and kept here between requests.
    private static var ddiPaths: DDIPaths {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return DDIPaths.default(in: library.appendingPathComponent("StikJIT"))
    }
    #endif

    /// StikJIT reads the pairing file from disk: a file of this process's own,
    /// gone again as soon as `body` is done. Never logged.
    private static func withPairingFile<T>(_ request: [AnyHashable: Any], _ body: (URL) throws -> T) throws -> T {
        guard let pairing = request["pairing"] as? Data, !pairing.isEmpty else { throw HelperError("no pairing file") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        try pairing.write(to: url, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }
}

struct HelperError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
