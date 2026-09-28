import AppKit
import ApplicationServices
import KutuCore

public protocol WindowResolving: AnyObject {
    func element(for id: WindowID) -> AXUIElement?
}

/// Hides windows by moving them off-screen and restores them to the exact frame
/// they had. Saved frames are flushed to disk on every mutation, because a lost
/// frame means a window the user cannot reach.
public final class Parker {
    /// Bottom-right: macOS clamps this to leave only a 40px-by-title-bar
    /// fragment. The top-left equivalent leaves a full-height 40px strip.
    public static let parkPoint = CGPoint(x: 60000, y: 60000)

    /// Held strongly and deliberately. Nothing in the dependency graph points
    /// back at Parker (WindowRegistry never references it), so there is no
    /// cycle to break — and a dropped resolver would silently turn `park` and
    /// `unpark` into no-ops, which fails in exactly the direction that strands
    /// windows.
    private let resolver: any WindowResolving
    private let store: StateStore

    public init(resolver: any WindowResolving, store: StateStore) {
        self.resolver = resolver
        self.store = store
    }

    public var parkedIDs: Set<WindowID> {
        Set(store.parkedFrames.keys.compactMap(WindowID.init))
    }

    public func isParked(_ id: WindowID) -> Bool {
        store.parkedFrames[String(id)] != nil
    }

    @discardableResult
    public func park(_ ref: KutuWindow) -> Bool {
        guard !StageManagerGuard.isEnabled else { return false }
        guard !ref.isFullScreen else { return false }
        guard !isParked(ref.id), let element = resolver.element(for: ref.id) else { return false }

        // A window already sitting at the park corner is not somewhere the user
        // put it — macOS relocates windows when a display is disconnected. Its
        // real position is already lost, so record a sane substitute rather
        // than either trusting the junk frame or refusing to act: refusing
        // leaves an already-off-screen window hidden with no restore frame at
        // all, which is how two windows became unrecoverable.
        // `ref.frame` is Accessibility-space; see `unpark` for why the screens
        // are flipped to match rather than compared raw.
        let screens = NSScreen.screens.map { SliverMask.accessibilityRect(fromAppKit: $0.frame) }
        var frameToSave = ref.frame
        if Geometry.looksParked(ref.frame, screens: screens) {
            frameToSave = Geometry.defaultFrame(forSize: ref.frame.size, screens: screens)
            NSLog("kutu: window \(ref.id) (\(ref.appName)) was already at the park corner; its original position is unknown, restoring to a default")
        }

        // Record before moving: if kutu dies between the two, recovery still
        // knows where the window belongs. The reverse order can lose it.
        guard store.mutate({ $0.parkedFrames[String(ref.id)] = frameToSave }) else {
            NSLog("kutu: refusing to park \(ref.id) — its frame could not be saved")
            return false
        }
        guard AXBridge.setPosition(element, Parker.parkPoint) else {
            store.mutate { $0.parkedFrames.removeValue(forKey: String(ref.id)) }
            return false
        }
        return true
    }

    @discardableResult
    public func unpark(_ id: WindowID) -> Bool {
        guard let frame = store.parkedFrames[String(id)],
              let element = resolver.element(for: id) else { return false }

        // This is stale data, not the clamp macOS applies at park time: the
        // saved frame was valid when it was recorded, but a display that has
        // since been detached can leave it pointing at coordinates that no
        // longer exist on any screen. The stored frame itself is left alone —
        // a display often comes back, and the original position is what the
        // user wants then — this only substitutes at the moment of
        // restoring, so an unreachable save never becomes an unreachable
        // restore.
        //
        // `frame` is Accessibility-space (top-left origin, y down); `NSScreen`
        // is AppKit-space (bottom-left origin, y up). Both describe the same
        // displays, but comparing them without converting would compare
        // numbers that do not mean the same thing — the screens are flipped
        // into Accessibility space here so they line up with `frame`.
        let axScreens = NSScreen.screens.map { SliverMask.accessibilityRect(fromAppKit: $0.frame) }
        let target = Geometry.reachable(frame, screens: axScreens)
        // Parking can shrink the window too: macOS clamps it onto whichever
        // display holds the park corner, and a window taller than that
        // display is cut down to fit. Position alone would bring it back at
        // the smaller size, so restore the size once it is on its own display
        // again — then re-place it, since a resize can nudge the origin. A
        // failed resize is not a failed unpark; the window is reachable
        // either way.
        let moved = AXBridge.withEnhancedUIDisabled(for: element) {
            guard AXBridge.setPosition(element, target.origin) else { return false }
            if AXBridge.setSize(element, target.size) {
                AXBridge.setPosition(element, target.origin)
            }
            return true
        }
        if moved {
            AXBridge.raise(element)
            store.mutate { $0.parkedFrames.removeValue(forKey: String(id)) }
        }
        return moved
    }

    /// The safety valve. Restores every window kutu believes it has parked,
    /// including ones parked by a previous, crashed run.
    ///
    /// Deliberately does NOT clear `parkedFrames` wholesale afterwards.
    /// `unpark` already removes each entry it succeeds on, so a blanket
    /// `removeAll()` would discard the saved frame of any window that FAILED
    /// to unpark — destroying the only record of where that window belongs and
    /// stranding it off-screen permanently. Failures must keep their frames so
    /// a later attempt, or `reconcile` at next launch, can still recover them.
    public func unparkAll() {
        for key in store.parkedFrames.keys {
            if let id = WindowID(key) { _ = unpark(id) }
        }
    }

    /// Called at launch. Windows the saved state says are parked but which no
    /// longer belong to a hidden box are restored, so a crash mid-switch or a
    /// config change can never leave a window unreachable.
    public func reconcile(activeBox: String,
                          membership: Membership,
                          pinnedBundleIDs: Set<String>,
                          windows: [KutuWindow]) {
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let liveIDs = AXBridge.liveWindowIDs()

        for key in store.parkedFrames.keys {
            guard let id = WindowID(key) else {
                store.mutate { $0.parkedFrames.removeValue(forKey: key) }
                continue
            }
            guard let ref = byID[id] else {
                // Missing from the Accessibility sweep is NOT proof the window
                // is gone: an app still launching, or merely too busy to answer
                // within the messaging timeout, is absent from the sweep while
                // its window still exists. Discarding that frame would strand
                // the window off-screen permanently — the one outcome this
                // whole design exists to prevent. Only drop the frame when the
                // window server agrees the window no longer exists.
                if !liveIDs.contains(id) {
                    store.mutate { $0.parkedFrames.removeValue(forKey: key) }
                }
                continue
            }
            let shouldStayHidden: Bool
            switch membership.tier(of: ref, pinnedBundleIDs: pinnedBundleIDs) {
            case .pinned:
                shouldStayHidden = false
            case .boxed(let box):
                shouldStayHidden = box != activeBox
            case .loose:
                shouldStayHidden = activeBox != Membership.lobby
            }
            if !shouldStayHidden { _ = unpark(id) }
        }
    }
}
