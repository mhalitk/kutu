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
    public func forget(_ id: WindowID) {
        store.mutate { $0.membership.forget(id) }
    }

    public func switchTo(_ box: String) {
        registry.refresh()
        let plan = SwitchPlan.compute(all: registry.windows,
                                      membership: store.membership,
                                      pinnedBundleIDs: Set(config.pinnedBundleIDs),
                                      target: box)
        let byID = Dictionary(uniqueKeysWithValues: registry.windows.map { ($0.id, $0) })

        for id in plan.toPark {
            guard let ref = byID[id] else { continue }
            _ = parker.park(ref)
        }
        for id in plan.toUnpark {
            _ = parker.unpark(id)
        }

        store.mutate { $0.activeBox = box }
        activatePrimaryApp(of: box, among: plan.toUnpark, byID: byID)
        onChange?()
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
