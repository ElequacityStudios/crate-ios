// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

/// The VM's screen, scaled to fit, and the person's touches and keys as the
/// VM's tablet and keyboard. A tap clicks, a drag holds the button down, a long
/// press clicks the right button, and two fingers scroll. A mouse or trackpad
/// is the desktop's own: moving it moves the guest's pointer (iPadOS's hides
/// over the picture, where the guest draws one), its buttons click as
/// themselves, and its wheel or two-finger scroll scrolls what's under it.
/// Typing comes from iOS's keyboard (`showsKeyboard`), with a row of extra keys
/// above it (DisplayKeyBar), or a hardware one, as Linux key codes.
struct DisplayView: UIViewRepresentable {
    let bridge: DisplayBridge
    @Binding var showsKeyboard: Bool
    /// Set once the first frame is on screen.
    @Binding var hasPicture: Bool
    /// Where in the view the picture goes, when not all of it is open: above
    /// the fold, with iPhone Duo half open like a laptop.
    var openRegion: CGRect?

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
        view.openRegion = openRegion
        if showsKeyboard, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !showsKeyboard {
            if view.isFirstResponder { _ = view.resignFirstResponder() }
            view.takeHardwareKeys()
        }
    }

    static func dismantleUIView(_ view: ScreenView, coordinator: ()) {
        view.bridge.disconnect()
    }

    final class ScreenView: UIView, UIKeyInput, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
        let bridge: DisplayBridge
        var onKeyboardHidden: (() -> Void)?
        private var imageSize = CGSize.zero
        private var scrollCarry = CGPoint.zero
        /// The buttons the guest last heard were down, which the pointer
        /// keeps as it moves: a wheel turned mid-drag doesn't let go.
        private var pressed: UInt32 = 0
        /// Where the mouse last hovered over the view.
        private var mouse: CGPoint?
        /// What only a mouse or trackpad drives, never a touch.
        private var pointerOnly: [UIGestureRecognizer] = []
        /// What a mouse's primary button drives as a finger does, but its
        /// others don't: they click as themselves (rightClicked).
        private var primaryOnly: [UIGestureRecognizer] = []
        /// Hides iPadOS's pointer over the picture.
        private lazy var pointerInteraction = UIPointerInteraction(delegate: self)
        /// The VM's screen, placed at screenRect.
        private let picture = CALayer()
        /// How much of the view's bottom the on-screen keyboard covers.
        private var keyboardOverlap: CGFloat = 0
        /// First responder while the on-screen keyboard is down, for a
        /// hardware keyboard's keys (takeHardwareKeys).
        private let keyCatcher = KeyCatcher()
        /// See DisplayView.openRegion. The picture moves as the iPhone folds,
        /// and the desktop takes the shape of where it now goes.
        var openRegion: CGRect? {
            didSet {
                guard openRegion != oldValue else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                placePicture()
                CATransaction.commit()
                fit()
            }
        }

        init(bridge: DisplayBridge) {
            self.bridge = bridge
            super.init(frame: .zero)
            backgroundColor = .black
            picture.magnificationFilter = .linear
            layer.addSublayer(picture)
            isMultipleTouchEnabled = true
            keyCatcher.owner = self
            addSubview(keyCatcher)

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))
            drag.maximumNumberOfTouches = 1
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled))
            scroll.minimumNumberOfTouches = 2
            scroll.maximumNumberOfTouches = 2
            tap.require(toFail: hold)

            // A mouse's or trackpad's scrolling comes as scroll events, which a
            // pan takes only when asked; allowing it no touches keeps it off
            // the fingers' gestures. Wheel clicks and a trackpad's glide are
            // told apart only by which pan iPadOS hands them to.
            let wheel = UIPanGestureRecognizer(target: self, action: #selector(wheeled))
            wheel.allowedScrollTypesMask = .discrete
            let glide = UIPanGestureRecognizer(target: self, action: #selector(glided))
            glide.allowedScrollTypesMask = .continuous
            for pan in [wheel, glide] {
                pan.allowedTouchTypes = []
                pan.maximumNumberOfTouches = 0
            }
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered))
            // A mouse's click comes as a touch, its buttons in the event.
            // buttonMaskRequired is checked only for a mouse, so a finger's tap
            // would do for these too, but tap takes it first.
            let rightClick = UITapGestureRecognizer(target: self, action: #selector(rightClicked))
            rightClick.buttonMaskRequired = .secondary
            let middleClick = UITapGestureRecognizer(target: self, action: #selector(middleClicked))
            middleClick.buttonMaskRequired = .button(3)
            rightClick.require(toFail: tap)
            middleClick.require(toFail: tap)
            pointerOnly = [wheel, glide, hover]
            primaryOnly = [drag, hold]

            for recognizer in [tap, drag, hold, scroll, wheel, glide, hover, rightClick, middleClick] {
                recognizer.delegate = self
                addGestureRecognizer(recognizer)
            }
            addInteraction(pointerInteraction)

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(keyboardWillChange),
                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            center.addObserver(self, selector: #selector(keyboardWillHide),
                               name: UIResponder.keyboardWillHideNotification, object: nil)
            center.addObserver(self, selector: #selector(keyboardDidHide),
                               name: UIResponder.keyboardDidHideNotification, object: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func show(_ image: CGImage) {
            let size = CGSize(width: image.width, height: image.height)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            picture.contents = image
            if size != imageSize {
                imageSize = size
                placePicture()
            }
            CATransaction.commit()
        }

        /// The picture to screenRect, and iPadOS's pointer told where it now
        /// hides (pointerInteraction(_:regionFor:defaultRegion:)).
        private func placePicture() {
            picture.frame = screenRect
            pointerInteraction.invalidate()
        }

        /// The guest's desktop takes the view's shape (DisplayBridge.fit), but
        /// not while the keyboard shows: it covers the screen, and a size made
        /// around it would stay after it goes. Folding refits whatever the
        /// keyboard: it stays below the fold.
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placePicture()
            CATransaction.commit()
            if keyboardOverlap == 0 { fit() }
        }

        /// The guest's desktop takes the shape of where the picture goes: the
        /// view, or above the fold, which is its own shape and not remembered.
        private func fit() {
            if let openRegion {
                bridge.fit(openRegion.intersection(bounds).size, window: nil)
            } else {
                bridge.fit(bounds.size, window: window?.bounds.size ?? bounds.size)
            }
        }

        /// The keyboard came up or changed size: the picture moves clear of it.
        @objc private func keyboardWillChange(_ note: Notification) {
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let screen = window?.windowScene?.screen else { return }
            let frame = convert(end, from: screen.coordinateSpace)
            moveClearOfKeyboard(max(0, bounds.maxY - frame.minY), note)
        }

        @objc private func keyboardWillHide(_ note: Notification) {
            moveClearOfKeyboard(0, note)
        }

        /// The size it's laid out at now, in case the iPhone turned meanwhile.
        @objc private func keyboardDidHide() {
            fit()
        }

        private func moveClearOfKeyboard(_ overlap: CGFloat, _ note: Notification) {
            guard overlap != keyboardOverlap else { return }
            keyboardOverlap = overlap
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            placePicture()
            CATransaction.commit()
        }

        // MARK: Touch as the tablet

        /// Where the screen sits in the view: scaled to fit the open region
        /// (all of the view, or the part above the fold) and centred in it, or
        /// with the keyboard up, centred in what the keyboard leaves showing
        /// (at the top, if it's taller than that), at the same size.
        private var screenRect: CGRect {
            let region = openRegion.map { $0.intersection(bounds) } ?? bounds
            guard imageSize.width > 0, imageSize.height > 0, !region.isEmpty else { return bounds }
            let scale = min(region.width / imageSize.width, region.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let bottom = keyboardOverlap > 0 ? min(region.maxY, bounds.height - keyboardOverlap) : region.maxY
            let open = bottom - region.minY
            let y = region.minY + max(0, (open - size.height) / 2)
            return CGRect(x: region.midX - size.width / 2, y: y, width: size.width, height: size.height)
        }

        private func point(_ recognizer: UIGestureRecognizer, buttons: UInt32) {
            // Back from something else that took the keys, such as a sheet.
            takeHardwareKeys()
            move(to: recognizer.location(in: self), buttons: buttons)
        }

        /// The guest's pointer to `location`, with `buttons` down, or those
        /// already down. It doesn't take the keys, as point does: a mouse
        /// passing over the picture, or scrolling it, isn't a click on it.
        private func move(to location: CGPoint, buttons: UInt32? = nil) {
            if let buttons { pressed = buttons }
            let rect = screenRect
            bridge.pointer(x: (location.x - rect.minX) / rect.width,
                           y: (location.y - rect.minY) / rect.height, buttons: pressed)
        }

        private func click(_ recognizer: UIGestureRecognizer, buttons: UInt32) {
            point(recognizer, buttons: 0)
            point(recognizer, buttons: buttons)
            point(recognizer, buttons: 0)
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            click(recognizer, buttons: 1)
        }

        @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
            // A mouse dragging sends no hovers: its place is where it drags,
            // so a wheel turned mid-drag scrolls there, button still down.
            mouse = recognizer.location(in: self)
            switch recognizer.state {
            case .began, .changed: point(recognizer, buttons: 1)
            default: point(recognizer, buttons: 0)
            }
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            click(recognizer, buttons: 2)
        }

        @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began {
                scrollCarry = .zero
                point(recognizer, buttons: 0)
            }
            scrollByDistance(recognizer)
        }

        /// A trackpad's two-finger scroll, or a Magic Mouse's, as two fingers
        /// on the screen.
        @objc private func glided(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began {
                scrollCarry = .zero
                moveToMouse(recognizer)
            }
            scrollByDistance(recognizer)
        }

        /// A mouse's wheel: a notch a click, the content following the wheel as
        /// in iPadOS's own scroll views. Apple doesn't say how far a click
        /// moves the pan, so it's the scroll events that move it that count,
        /// taken to be one a click, not the distance.
        @objc private func wheeled(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { moveToMouse(recognizer) }
            let moved = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            let notch = { (distance: CGFloat) -> Int32 in distance < 0 ? 1 : distance > 0 ? -1 : 0 }
            let dx = notch(moved.x), dy = notch(moved.y)
            if dx != 0 || dy != 0 { bridge.scroll(dx: dx, dy: dy) }
        }

        /// The guest's pointer to the mouse, so its wheel or trackpad scrolls
        /// what's under it, though a finger may have moved the pointer since.
        /// That's where it last hovered: a scroll pan's own location runs on
        /// ahead with the scrolling. Only before any hover is it all there is.
        private func moveToMouse(_ scroll: UIPanGestureRecognizer) {
            move(to: mouse ?? scroll.location(in: self))
        }

        /// The mouse moving with no button down, when iPadOS sends no touches.
        /// Its going (leaving the view, say) isn't a move: the pointer stays
        /// where it last was, not where the end puts it, the view's corner.
        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let location = recognizer.location(in: self)
                mouse = location
                move(to: location)
            default: break
            }
        }

        /// A mouse's right button, or a trackpad's two-finger click, as the
        /// long press.
        @objc private func rightClicked(_ recognizer: UITapGestureRecognizer) {
            click(recognizer, buttons: 2)
        }

        @objc private func middleClicked(_ recognizer: UITapGestureRecognizer) {
            click(recognizer, buttons: 4)
        }

        /// A mouse's other buttons pressed aren't the left one held down, or a
        /// long press: they click as themselves, and nothing else sees them.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
            !primaryOnly.contains(recognizer) || event.buttonMask.isSubset(of: .primary)
        }

        /// The mouse moving or scrolling goes along with whatever else is
        /// going on, such as a drag the wheel turns in.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            pointerOnly.contains(recognizer) || pointerOnly.contains(other)
        }

        /// A wheel notch per 20 points, the content following the fingers.
        private func scrollByDistance(_ recognizer: UIPanGestureRecognizer) {
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

        // MARK: iPadOS's pointer

        /// Hidden over the picture, where the guest draws its own, so there's
        /// one; over the bars beside it, as anywhere else.
        func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                                defaultRegion: UIPointerRegion) -> UIPointerRegion? {
            let rect = screenRect
            return rect.contains(request.location) ? UIPointerRegion(rect: rect) : nil
        }

        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            .hidden()
        }

        // MARK: Keys as the keyboard

        override var canBecomeFirstResponder: Bool { true }

        /// Only a first responder gets a hardware keyboard's presses, and this
        /// view as one brings up the on-screen keyboard too. So while that's
        /// down, keyCatcher is first responder instead.
        func takeHardwareKeys() {
            guard window != nil, !isFirstResponder, !keyCatcher.isFirstResponder else { return }
            keyCatcher.becomeFirstResponder()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            takeHardwareKeys()
        }

        /// Esc, Ctrl, Super, Tab, arrows and the rest, above the keyboard.
        private lazy var keyBar: DisplayKeyBar = {
            let bar = DisplayKeyBar()
            bar.onKey = { [weak self] code, down in self?.bridge.key(code, down: down) }
            bar.onDismiss = { [weak self] in _ = self?.resignFirstResponder() }
            return bar
        }()

        override var inputAccessoryView: UIView? { keyBar }

        override func resignFirstResponder() -> Bool {
            keyBar.releaseAll()
            let resigned = super.resignFirstResponder()
            if resigned { onKeyboardHidden?() }
            return resigned
        }

        var hasText: Bool { true }

        func insertText(_ text: String) {
            withLatchedModifiers {
                for character in text {
                    guard let stroke = LinuxKeys.stroke(for: character) else { continue }
                    if stroke.shift { bridge.key(LinuxKeys.leftShift, down: true) }
                    bridge.key(stroke.code, down: true)
                    bridge.key(stroke.code, down: false)
                    if stroke.shift { bridge.key(LinuxKeys.leftShift, down: false) }
                }
            }
        }

        func deleteBackward() {
            withLatchedModifiers {
                bridge.key(14, down: true)
                bridge.key(14, down: false)
            }
        }

        /// The key bar's latched Ctrl and Super, held around a keystroke from
        /// the on-screen keyboard.
        private func withLatchedModifiers(_ keystroke: () -> Void) {
            let modifiers = keyBar.takeModifiers()
            for code in modifiers { bridge.key(code, down: true) }
            keystroke()
            for code in modifiers.reversed() { bridge.key(code, down: false) }
        }

        /// The key bar's latched Ctrl and Super, held while a hardware key is.
        private var latchedForPress: [UInt16] = []

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
                let isModifier = LinuxKeys.modifiers.contains(code)
                if down, !isModifier {
                    latchedForPress = keyBar.takeModifiers()
                    for modifier in latchedForPress { bridge.key(modifier, down: true) }
                }
                bridge.key(code, down: down)
                if !down, !isModifier {
                    for modifier in latchedForPress.reversed() { bridge.key(modifier, down: false) }
                    latchedForPress = []
                }
                handled = true
            }
            return handled
        }
    }

    /// A first responder that isn't text input, so it brings up no keyboard,
    /// and hands its presses to ScreenView. It's left out of ScreenView's
    /// responder chain, or UIKit would show ScreenView's key bar for it.
    final class KeyCatcher: UIView {
        weak var owner: ScreenView?

        override var canBecomeFirstResponder: Bool { true }
        override var next: UIResponder? { owner?.next }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            owner?.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            owner?.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            owner?.pressesCancelled(presses, with: event)
        }
    }
}
