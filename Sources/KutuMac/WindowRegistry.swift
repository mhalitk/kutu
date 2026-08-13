import AppKit
import ApplicationServices
import KutuCore

/// The live inventory of managed windows. Driven by Accessibility and workspace
/// notifications rather than polling, so it stays current without burning CPU.
public final class WindowRegistry: NSObject, WindowResolving {
    public var onWindowAdded: ((KutuWindow) -> Void)?
    public var onWindowRemoved: ((WindowID) -> Void)?

    private var byID: [WindowID: ManagedWindow] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var running = false

    public var windows: [KutuWindow] { byID.values.map(\.ref) }

    public func element(for id: WindowID) -> AXUIElement? { byID[id]?.element }

    public func start() {
        guard !running else { return }
        running = true
        refresh()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    public func stop() {
        guard running else { return }
        running = false
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                  AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Full resweep. Cheap enough to run on demand (12 windows measured at well
    /// under a frame) and the recovery path when a notification is missed.
    public func refresh() {
        let current = AXBridge.allStandardWindows()
        let currentIDs = Set(current.map(\.ref.id))
        let knownIDs = Set(byID.keys)

        for window in current where !knownIDs.contains(window.ref.id) {
            byID[window.ref.id] = window
            onWindowAdded?(window.ref)
        }
        for id in knownIDs.subtracting(currentIDs) {
            byID.removeValue(forKey: id)
            onWindowRemoved?(id)
        }
        // Refresh frames of windows we already knew about.
        for window in current where knownIDs.contains(window.ref.id) {
            byID[window.ref.id] = window
        }
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid > 0 else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let registry = Unmanaged<WindowRegistry>.fromOpaque(context).takeUnretainedValue()
            registry.refresh()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let appElement = AXBridge.appElement(pid: pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification,
                             kAXUIElementDestroyedNotification,
                             kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, appElement, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        // Applications are not immediately ready to answer AX queries.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.observe(app)
            self?.refresh()
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        observers.removeValue(forKey: app.processIdentifier)
        refresh()
    }
}
