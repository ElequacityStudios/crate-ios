// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ObjectiveC
import UIKit

private var crateHomeIndicatorChildKey: UInt8 = 0
private var cratePointerLockChildKey: UInt8 = 0
private var crateSystemGesturesChildKey: UInt8 = 0
private var crateIgnoreIndirectPointerKey: UInt8 = 0

/// SwiftUI doesn't forward UIKit's home-indicator and pointer-lock preferences
/// from a representable's controller. UTM uses these child-controller hooks
/// for the same reason; keep the preference on the actual VM screen controller
/// and explicitly make SwiftUI's hosting controller ask it.
enum CrateUIKitPatches {
    static let install: Void = {
        exchange(
            #selector(getter: UIViewController.childForHomeIndicatorAutoHidden),
            #selector(getter: UIViewController.crate_childForHomeIndicatorAutoHidden),
            on: UIViewController.self
        )
        exchange(
            #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures),
            #selector(getter: UIViewController.crate_childForScreenEdgesDeferringSystemGestures),
            on: UIViewController.self
        )
        if #available(iOS 26.0, *) {
            exchange(
                #selector(getter: UIViewController.childViewControllerForPointerLock),
                #selector(getter: UIViewController.crate_childViewControllerForPointerLock),
                on: UIViewController.self
            )
        }
        exchange(
            #selector(UIWindow.sendEvent(_:)),
            #selector(UIWindow.crate_sendEvent(_:)),
            on: UIWindow.self
        )
    }()

    private static func exchange(_ original: Selector, _ replacement: Selector, on type: AnyClass) {
        guard let originalMethod = class_getInstanceMethod(type, original),
              let replacementMethod = class_getInstanceMethod(type, replacement) else {
            assertionFailure("Crate couldn't install a UIKit input patch: \(NSStringFromSelector(original))")
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension UIViewController {
    @objc fileprivate dynamic var crate_childForHomeIndicatorAutoHidden: UIViewController? {
        objc_getAssociatedObject(self, &crateHomeIndicatorChildKey) as? UIViewController
    }

    @objc fileprivate dynamic var crate_childViewControllerForScreenEdgesDeferringSystemGestures: UIViewController? {
        objc_getAssociatedObject(self, &crateSystemGesturesChildKey) as? UIViewController
    }

    @available(iOS 26.0, *)
    @objc fileprivate dynamic var crate_childViewControllerForPointerLock: UIViewController? {
        objc_getAssociatedObject(self, &cratePointerLockChildKey) as? UIViewController
    }

    func crate_setPointerLockPreferencesChild(_ child: UIViewController?) {
        _ = CrateUIKitPatches.install
        objc_setAssociatedObject(self, &crateHomeIndicatorChildKey, child, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &crateSystemGesturesChildKey, child, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        if #available(iOS 26.0, *) {
            objc_setAssociatedObject(self, &cratePointerLockChildKey, child, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }
}

extension UIWindow {
    var crate_ignoresIndirectPointerTouches: Bool {
        get {
            (objc_getAssociatedObject(self, &crateIgnoreIndirectPointerKey) as? NSNumber)?.boolValue ?? false
        }
        set {
            _ = CrateUIKitPatches.install
            objc_setAssociatedObject(
                self,
                &crateIgnoreIndirectPointerKey,
                NSNumber(value: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// Matches UTM's workaround: ignore indirect-pointer touch events while
    /// the guest owns the pointer, but still dispatch the event so UIKit's
    /// subsequent touch sequence remains consistent.
    @objc fileprivate dynamic func crate_sendEvent(_ event: UIEvent) {
        if crate_ignoresIndirectPointerTouches, event.type == .touches {
            let selector = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
            for touch in event.touches(for: self) ?? [] where touch.type == .indirectPointer {
                touch.perform(
                    selector,
                    with: CGPoint(x: -1, y: -1),
                    with: true
                )
            }
        }
        crate_sendEvent(event)
    }
}
