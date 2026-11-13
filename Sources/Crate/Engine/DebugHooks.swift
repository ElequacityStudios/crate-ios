#if DEBUG
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Debug builds only: a running VM driven from a Mac, which can read and write
/// the app's container (devicectl) but can't see the screen or type. Every
/// second it looks in `Library/Caches/debug/`:
///
/// - `screen`: the display's current frame goes to `screen.png`.
/// - `command.txt`: its text is typed into the serial console.
///
/// Each request file is removed once it's done.
@MainActor
final class DebugHooks {
    nonisolated static let folder = URL.cachesDirectory.appendingPathComponent("debug")
    private var timer: Timer?

    func start(console: ConsoleBridge, display: DisplayBridge) {
        stop()
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Self.poll(console: console, display: display)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private nonisolated static func poll(console: ConsoleBridge, display: DisplayBridge) {
        let files = FileManager.default
        let screen = folder.appendingPathComponent("screen")
        if files.fileExists(atPath: screen.path) {
            try? files.removeItem(at: screen)
            if let image = display.snapshot() {
                let url = folder.appendingPathComponent("screen.png") as CFURL
                if let out = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(out, image, nil)
                    CGImageDestinationFinalize(out)
                }
            }
        }
        let command = folder.appendingPathComponent("command.txt")
        if let text = try? Data(contentsOf: command) {
            try? files.removeItem(at: command)
            console.send(ArraySlice(text))
        }
    }
}
#endif
