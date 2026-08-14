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
    private var isRefreshing = false
    private var hasSwept = false
    private var recheckPending = false

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
    ///
    /// Non-reentrant by design. The callbacks below fire mid-sweep, and a
    /// consumer that reacts by asking for another sweep would leave this one
    /// iterating a stale view of what was known — emitting duplicate added or
    /// removed events for the same window. One sweep at a time; the nested
    /// request is redundant anyway, since the outer sweep reconciles against
    /// live state.
    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // `onWindowAdded` means "appeared", not "seen for the first time by
        // this process". The initial sweep discovers every window already open,
        // and those carry persisted box membership — adopting them into the
        // active box would silently collapse every box into one.
        let isInitialSweep = !hasSwept
        hasSwept = true

        let current = AXBridge.allStandardWindows()
        let currentIDs = Set(current.map(\.ref.id))
        let knownIDs = Set(byID.keys)
        let liveIDs = AXBridge.liveWindowIDs()

        for window in current where !knownIDs.contains(window.ref.id) {
            byID[window.ref.id] = window
            if !isInitialSweep { onWindowAdded?(window.ref) }
        }
        var deferredRemoval = false
        for id in knownIDs.subtracting(currentIDs) {
            // Absence from the Accessibility sweep is not death: an app blocked
            // past the messaging timeout vanishes from the sweep while its
            // windows still exist. Deleting a parked window's saved frame on
            // that evidence strands it permanently, so only the window server
            // settles it.
            guard !liveIDs.contains(id) else {
                // ...but the window server can also lag behind the Accessibility
                // notification that brought us here, and no further notification
                // is coming. Without a re-check the window would stay in `byID`
                // forever and its box membership and saved frame would never be
                // released.
                deferredRemoval = true
                continue
            }
            byID.removeValue(forKey: id)
            onWindowRemoved?(id)
        }
        // Refresh frames of windows we already knew about.
        for window in current where knownIDs.contains(window.ref.id) {
            byID[window.ref.id] = window
        }

        if deferredRemoval { scheduleRecheck() }
    }

    /// A removal skipped because the window server still lists the id needs a
    /// second look later: the notification that triggered this `refresh()` was
    /// the only one coming, so nothing else will prompt a re-check once the
    /// server catches up. Bounded to one in-flight timer so a burst of
    /// notifications (or a genuinely still-alive window that keeps deferring)
    /// cannot pile up timers on top of each other.
    private func scheduleRecheck() {
        guard running, !recheckPending else { return }
        recheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.running else { return }
            self.recheckPending = false
            self.refresh()
        }
    }

    /// An AXObserver holds an *unretained* pointer to self as its notification
    /// context, and CoreFoundation gives no zeroing-weak guarantee for it. A
    /// registry released while still observing would have the next notification
    /// dereference freed memory, so teardown cannot be left to the caller.
    /// Assumes start/stop/deinit occur on the run loop the sources were added
    /// to, which for kutu is always the main one.
    deinit {
        stop()
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
        // Applications are not immediately ready to answer AX queries, so this
        // is deferred — which means `stop()` can win the race. Re-check, or a
        // launch arriving during shutdown resurrects an observer on a registry
        // that is supposed to be dead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.running else { return }
            self.observe(app)
            self.refresh()
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        // Drop the run loop source explicitly rather than relying on the Mach
        // port dying: same reasoning as `stop()`, and it keeps teardown uniform.
        if let observer = observers.removeValue(forKey: app.processIdentifier) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                                  AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        refresh()
    }
}
