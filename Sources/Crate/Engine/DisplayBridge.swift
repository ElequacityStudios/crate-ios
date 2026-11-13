import CoreGraphics
import CrateEngine
import Foundation

/// The VM's screen, between crate's GPU thread and the display view, and the
/// view's input on its way back in.
///
/// crate hands over a frame with the part that changed marked: that part is
/// copied into a buffer of the whole screen, and the main thread is handed a
/// picture of it, a frame at a time however fast they come. crate makes frames
/// only while the display is active, which the view turns on while it shows.
final class DisplayBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var machine: OpaquePointer?
    /// The machine's one display.
    private let index: UInt32 = 0

    private var pixels: UnsafeMutableRawPointer?
    private var width = 0
    private var height = 0
    private var flushScheduled = false
    private var sink: (@MainActor (CGImage) -> Void)?
    private var wantsActive = false

    /// For crate_config_add_display; `self` outlives the machine.
    var callbacks: crate_display_callbacks {
        crate_display_callbacks(
            size: MemoryLayout<crate_display_callbacks>.size,
            context: Unmanaged.passUnretained(self).toOpaque(),
            frame: { context, _, frame in
                guard let context, let frame else { return }
                Unmanaged<DisplayBridge>.fromOpaque(context).takeUnretainedValue().take(frame.pointee)
            })
    }

    deinit {
        pixels?.deallocate()
    }

    func attach(machine: OpaquePointer) {
        let active = lock.withLock { () -> Bool in
            self.machine = machine
            return wantsActive
        }
        if active { crate_display_set_active(machine, index, true) }
    }

    func detach() {
        lock.withLock { machine = nil }
    }

    // MARK: - The view's side, on the main thread

    /// Starts handing `sink` pictures, and asks crate for frames.
    @MainActor
    func connect(_ sink: @escaping @MainActor (CGImage) -> Void) {
        let machine = lock.withLock { () -> OpaquePointer? in
            self.sink = sink
            wantsActive = true
            return self.machine
        }
        if let machine { crate_display_set_active(machine, index, true) }
        if let image = picture() { sink(image) }
    }

    /// Stops the frames while nothing shows them: they cost a copy each.
    @MainActor
    func disconnect() {
        let machine = lock.withLock { () -> OpaquePointer? in
            sink = nil
            wantsActive = false
            return self.machine
        }
        if let machine { crate_display_set_active(machine, index, false) }
    }

    /// The screen's size in pixels, once a frame has come.
    var size: CGSize {
        lock.withLock { CGSize(width: width, height: height) }
    }

    // Input, for the machine's virtio keyboard and tablet.

    func key(_ code: UInt16, down: Bool) {
        lock.withLock {
            guard let machine else { return }
            crate_input_key(machine, code, down)
        }
    }

    /// `x` and `y` from 0 to 1 across the screen.
    func pointer(x: Double, y: Double, buttons: UInt32) {
        let scale = 32767.0
        let px = UInt32(max(0, min(1, x)) * scale)
        let py = UInt32(max(0, min(1, y)) * scale)
        lock.withLock {
            guard let machine else { return }
            crate_input_pointer(machine, px, py, buttons)
        }
    }

    func scroll(dx: Int32, dy: Int32) {
        lock.withLock {
            guard let machine else { return }
            crate_input_scroll(machine, dx, dy)
        }
    }

    // MARK: - crate's side, on the GPU's thread

    private func take(_ frame: crate_frame) {
        guard let source = frame.pixels else { return }
        lock.withLock {
            let w = Int(frame.width), h = Int(frame.height)
            var dirtyX = Int(frame.dirty_x), dirtyY = Int(frame.dirty_y)
            var dirtyW = Int(frame.dirty_width), dirtyH = Int(frame.dirty_height)
            if w != width || h != height || pixels == nil {
                // A new size: take the whole frame.
                pixels?.deallocate()
                pixels = UnsafeMutableRawPointer.allocate(byteCount: w * h * 4, alignment: 16)
                width = w
                height = h
                (dirtyX, dirtyY, dirtyW, dirtyH) = (0, 0, w, h)
                AppLog.write("display: \(w)x\(h)")
            }
            guard let pixels, dirtyW > 0, dirtyH > 0 else { return }
            let stride = Int(frame.stride)
            for row in dirtyY..<min(dirtyY + dirtyH, h) {
                let from = source.advanced(by: row * stride + dirtyX * 4)
                let to = pixels.advanced(by: (row * w + dirtyX) * 4)
                to.copyMemory(from: from, byteCount: min(dirtyW, w - dirtyX) * 4)
            }
            guard sink != nil, !flushScheduled else { return }
            flushScheduled = true
            DispatchQueue.main.async { self.flush() }
        }
    }

    @MainActor
    private func flush() {
        let sink = lock.withLock { () -> (@MainActor (CGImage) -> Void)? in
            flushScheduled = false
            return self.sink
        }
        if let sink, let image = picture() { sink(image) }
    }

    #if DEBUG
    /// The screen so far, for DebugHooks.
    func snapshot() -> CGImage? { picture() }
    #endif

    /// The screen so far, as a picture: a copy, so crate can keep drawing.
    private func picture() -> CGImage? {
        lock.withLock {
            guard let pixels, width > 0, height > 0 else { return nil }
            let data = Data(bytes: pixels, count: width * height * 4) as CFData
            guard let provider = CGDataProvider(data: data) else { return nil }
            // Red, green, blue, unused: as crate lays a pixel out.
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
