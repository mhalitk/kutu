import AppKit
import KutuCore

/// cmd+tab activates an application, not a window. If every window of the
/// activated application is parked, the user gets a frontmost app with nothing
/// on screen. This guard notices and reports it — it does not decide to
/// switch boxes on the user's behalf.
public final class ActivationGuard: NSObject {
    /// Fired when the user activated an application whose windows all live in
    /// another box. Reports what happened; it does not decide what to do about
    /// it — that is the delegate's call, and it depends on configuration.
    public var onActivatedHiddenApp: ((_ appName: String, _ box: String) -> Void)?

    private let registry: WindowRegistry
    private let parker: Parker
    private let switcher: Switcher
    private var pinnedBundleIDs: Set<String>
    private var suppressedUntil = Date.distantPast
    private var running = false

    public init(registry: WindowRegistry, parker: Parker, switcher: Switcher,
                pinnedBundleIDs: Set<String>) {
        self.registry = registry
        self.parker = parker
        self.switcher = switcher
        self.pinnedBundleIDs = pinnedBundleIDs
    }

    public func start() {
        guard !running else { return }
        running = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    public func stop() {
        guard running else { return }
        running = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// kutu activates applications itself during a switch; without this the
    /// guard would react to its own work and ping-pong between boxes.
    public func suppress(for seconds: TimeInterval) {
        suppressedUntil = Date().addingTimeInterval(seconds)
    }

    public func reload(pinnedBundleIDs: Set<String>) {
        self.pinnedBundleIDs = pinnedBundleIDs
    }

    @objc private func appActivated(_ note: Notification) {
        guard Date() >= suppressedUntil,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }

        let windows = registry.windows.filter { $0.pid == app.processIdentifier }
        guard !windows.isEmpty else { return }
        // Only act when the user has been left with nothing to look at.
        guard windows.allSatisfy({ parker.isParked($0.id) }) else { return }

        // `registry.windows` comes from a dictionary, so its order is
        // arbitrary. When an app's parked windows span more than one box —
        // a browser with windows in two projects, say — picking `.first`
        // would send the user somewhere different on identical input. Sort so
        // the same cmd+tab always lands in the same box.
        let target = windows
            .map { switcher.membership.boxName(for: $0, pinnedBundleIDs: pinnedBundleIDs) }
            .filter { $0 != switcher.activeBox }
            .sorted()
            .first
        guard let target else { return }
        onActivatedHiddenApp?(app.localizedName ?? "That app", target)
    }
}
