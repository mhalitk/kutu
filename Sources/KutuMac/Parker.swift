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

        // Record before moving: if kutu dies between the two, recovery still
        // knows where the window belongs. The reverse order can lose it.
        store.mutate { $0.parkedFrames[String(ref.id)] = ref.frame }
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
        let moved = AXBridge.setPosition(element, frame.origin)
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

        for key in store.parkedFrames.keys {
            guard let id = WindowID(key) else {
                store.mutate { $0.parkedFrames.removeValue(forKey: key) }
                continue
            }
            guard let ref = byID[id] else {
                // The window died while parked; the frame is meaningless now.
                store.mutate { $0.parkedFrames.removeValue(forKey: key) }
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
