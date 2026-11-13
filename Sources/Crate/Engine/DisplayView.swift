import SwiftUI
import UIKit

/// The VM's screen, scaled to fit, and the person's touches and keys as the
/// VM's tablet and keyboard. A tap clicks, a drag holds the button down, a long
/// press clicks the right button, and two fingers scroll. Typing comes from
/// iOS's keyboard (`showsKeyboard`) or a hardware one, as Linux key codes.
struct DisplayView: UIViewRepresentable {
    let bridge: DisplayBridge
    @Binding var showsKeyboard: Bool
    /// Set once the first frame is on screen.
    @Binding var hasPicture: Bool

    func makeUIView(context: Context) -> ScreenView {
        let view = ScreenView(bridge: bridge)
        view.onKeyboardHidden = { showsKeyboard = false }
        let hasPicture = $hasPicture
        bridge.connect { [weak view] image in
            view?.show(image)
            if !hasPicture.wrappedValue { hasPicture.wrappedValue = true }
        }
        return view
    }

    func updateUIView(_ view: ScreenView, context: Context) {
        if showsKeyboard, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !showsKeyboard, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ view: ScreenView, coordinator: ()) {
        view.bridge.disconnect()
    }

    final class ScreenView: UIView, UIKeyInput {
        let bridge: DisplayBridge
        var onKeyboardHidden: (() -> Void)?
        private var imageSize = CGSize.zero
        private var scrollCarry = CGPoint.zero

        init(bridge: DisplayBridge) {
            self.bridge = bridge
            super.init(frame: .zero)
            backgroundColor = .black
            layer.contentsGravity = .resizeAspect
            layer.magnificationFilter = .linear
            isMultipleTouchEnabled = true

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
            drag.maximumNumberOfTouches = 1
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled))
            scroll.minimumNumberOfTouches = 2
            scroll.maximumNumberOfTouches = 2
            tap.require(toFail: hold)
            for recognizer in [tap, drag, hold, scroll] { addGestureRecognizer(recognizer) }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func show(_ image: CGImage) {
            imageSize = CGSize(width: image.width, height: image.height)
            layer.contents = image
        }

        // MARK: Touch as the tablet

        /// Where the screen sits in the view, scaled to fit.
        private var screenRect: CGRect {
            guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        }

        private func point(_ recognizer: UIGestureRecognizer, buttons: UInt32) {
            let rect = screenRect
            let location = recognizer.location(in: self)
            bridge.pointer(x: (location.x - rect.minX) / rect.width,
                           y: (location.y - rect.minY) / rect.height, buttons: buttons)
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            point(recognizer, buttons: 0)
            point(recognizer, buttons: 1)
            point(recognizer, buttons: 0)
        }

        @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed: point(recognizer, buttons: 1)
            default: point(recognizer, buttons: 0)
            }
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            point(recognizer, buttons: 0)
            point(recognizer, buttons: 2)
            point(recognizer, buttons: 0)
        }

        /// A wheel notch per 20 points, the content following the fingers.
        @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began {
                scrollCarry = .zero
                point(recognizer, buttons: 0)
            }
            let moved = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            scrollCarry.x += moved.x
            scrollCarry.y += moved.y
            let notch: CGFloat = 20
            let dx = Int32(-scrollCarry.x / notch), dy = Int32(-scrollCarry.y / notch)
            if dx != 0 || dy != 0 {
                bridge.scroll(dx: dx, dy: dy)
                scrollCarry.x += CGFloat(dx) * notch
                scrollCarry.y += CGFloat(dy) * notch
            }
        }

        // MARK: Keys as the keyboard

        override var canBecomeFirstResponder: Bool { true }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onKeyboardHidden?() }
            return resigned
        }

        var hasText: Bool { true }

        func insertText(_ text: String) {
            for character in text {
                guard let stroke = LinuxKeys.stroke(for: character) else { continue }
                if stroke.shift { bridge.key(LinuxKeys.leftShift, down: true) }
                bridge.key(stroke.code, down: true)
                bridge.key(stroke.code, down: false)
                if stroke.shift { bridge.key(LinuxKeys.leftShift, down: false) }
            }
        }

        func deleteBackward() {
            bridge.key(14, down: true)
            bridge.key(14, down: false)
        }

        // What a terminal wants from the on-screen keyboard: nothing changed.
        var autocorrectionType: UITextAutocorrectionType = .no
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no
        var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
        var keyboardType: UIKeyboardType = .asciiCapable

        /// A hardware keyboard: each key down and up as itself, modifiers
        /// included, which iOS's text input would lose.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, down: true) { super.pressesBegan(presses, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, down: false) { super.pressesEnded(presses, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, down: false) { super.pressesCancelled(presses, with: event) }
        }

        private func forward(_ presses: Set<UIPress>, down: Bool) -> Bool {
            var handled = false
            for press in presses {
                guard let key = press.key, let code = LinuxKeys.code(for: key.keyCode) else { continue }
                bridge.key(code, down: down)
                handled = true
            }
            return handled
        }
    }
}
