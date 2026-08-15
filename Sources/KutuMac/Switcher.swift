import AppKit
import KutuCore

/// Applies a SwitchPlan to the real world. Parking happens before unparking so
/// the screen never shows both boxes at once.
public final class Switcher {
    public var onChange: (() -> Void)?

    private let registry: WindowRegistry
    private let parker: Parker
    private let store: StateStore
    private var config: KutuConfig

    public init(registry: WindowRegistry, parker: Parker, store: StateStore, config: KutuConfig) {
        self.registry = registry
        self.parker = parker
        self.store = store
        self.config = config
    }

    public var activeBox: String { store.activeBox }

    public var membership: Membership { store.membership }

    /// Configured boxes, plus any box a window has been assigned to, plus lobby.
    public var knownBoxes: [String] {
        var names = Set(config.boxes.map(\.name))
        let current = store.membership
        for window in registry.windows {
            if case .boxed(let box) = current.tier(of: window,
                                                            pinnedBundleIDs: Set(config.pinnedBundleIDs)) {
                names.insert(box)
            }
        }
        names.insert(Membership.lobby)
        return names.sorted { $0 == Membership.lobby ? false : ($1 == Membership.lobby ? true : $0 < $1) }
    }

    public func reload(config: KutuConfig) {
        self.config = config
    }

    public func assign(_ id: WindowID, to box: String) {
        store.mutate { $0.membership.assign(id, to: box) }
    }

    public func pin(_ id: WindowID) {
        store.mutate { $0.membership.pin(id) }
    }

    public func unpin(_ id: WindowID) {
        store.mutate { $0.membership.unpin(id) }
    }

    /// Called when a window closes. Without this, assignments for dead windows
    /// accumulate forever and window ids are eventually reused by macOS.
    ///
    /// The parked frame goes too. The window is gone, so the frame describes
    /// nothing — and leaving it behind is actively harmful once macOS reuses
    /// the id: `Parker.isParked` would report a brand-new window as already
    /// parked, so parking it silently no-ops (it stays visible when it should
    /// hide) or unparking it applies a dead window's frame (it jumps somewhere
    /// unexpected).
    public func forget(_ id: WindowID) {
        store.mutate {
            $0.membership.forget(id)
            $0.parkedFrames.removeValue(forKey: String(id))
        }
    }

    /// Runs once at launch. Ids do not survive a reboot, so the saved map
    /// necessarily holds entries for windows that no longer exist.
    ///
    /// Uses the window server rather than the Accessibility sweep, for exactly
    /// the reason `Parker.reconcile` does: an application too busy to answer AX
    /// within the messaging timeout is not a dead application, and treating it
    /// as one would unfile live windows.
    public func pruneDeadAssignments() {
        let living = AXBridge.liveWindowIDs()
        let before = store.membership
        store.mutate { $0.membership.prune(livingWindowIDs: living) }
        let removed = before.assignmentCount - store.membership.assignmentCount
        if removed > 0 {
            NSLog("kutu: pruned \(removed) assignment(s) for windows that no longer exist")
        }
    }

    public func switchTo(_ box: String) {
        registry.refresh()
        let (plan, byID) = applyPlan(target: box)
        store.mutate { $0.activeBox = box }
        activatePrimaryApp(of: box, among: plan.toUnpark, byID: byID)
        onChange?()
    }

    /// Re-applies the active box's plan after membership changes, so a window
    /// that no longer belongs here parks at once. Deliberately does not call
    /// `activatePrimaryApp`: this runs while the user is looking at a specific
    /// window, and yanking focus to some other application would be hostile.
    public func reapply() {
        registry.refresh()
        _ = applyPlan(target: store.activeBox)
        onChange?()
    }

    /// The park/unpark half of applying a plan, shared by `switchTo` (which
    /// also activates the target box's app) and `reapply` (which does not).
    private func applyPlan(target box: String) -> (plan: SwitchPlan, byID: [WindowID: KutuWindow]) {
        let plan = SwitchPlan.compute(all: registry.windows,
                                      membership: store.membership,
                                      pinnedBundleIDs: Set(config.pinnedBundleIDs),
                                      target: box)
        let byID = Dictionary(uniqueKeysWithValues: registry.windows.map { ($0.id, $0) })

        for id in plan.toPark {
            guard let ref = byID[id] else { continue }
            if !parker.park(ref) {
                NSLog("kutu: could not park window \(id) (\(ref.appName))")
            }
        }
        for id in plan.toUnpark {
            if !parker.unpark(id) && parker.isParked(id) {
                NSLog("kutu: could not unpark window \(id)")
            }
        }

        return (plan, byID)
    }

    /// Brings the box to the foreground. The first declared app would be more
    /// precise, but that lives in the manifest; falling back to any window of
    /// the box is correct and keeps this independent of the Launcher.
    private func activatePrimaryApp(of box: String, among visible: [WindowID],
                                    byID: [WindowID: KutuWindow]) {
        guard box != Membership.lobby else { return }
        let current = store.membership
        let candidates = visible.compactMap { byID[$0] }.filter {
            if case .boxed(let name) = current.tier(of: $0,
                                                    pinnedBundleIDs: Set(config.pinnedBundleIDs)) {
                return name == box
            }
            return false
        }
        guard let target = candidates.first,
              let app = NSRunningApplication(processIdentifier: target.pid) else { return }
        app.activate()
    }
}
