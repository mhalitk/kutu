import AppKit
import KutuCore
import KutuMac

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var registry: WindowRegistry!
    private var parker: Parker!
    private var switcher: Switcher!
    private var assigner: Assigner!
    private var menuBar: MenuBarController!
    private var mask: SliverMask!
    private var palette: PaletteWindow!
    private var activationGuard: ActivationGuard!
    private var hotKey: HotKey?
    private var statusServer: StatusServer!
    private var launcher: Launcher!
    private let tracker = StatusTracker()
    private var config = KutuConfig()

    static let configPath = KutuPaths.config

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXBridge.isTrusted else {
            AXBridge.requestTrust()
            presentTrustAlert()
            return
        }
        config = (try? KutuConfig.load(from: Self.configPath)) ?? KutuConfig()

        let store = StateStore(file: StateFile(path: StateFile.defaultPath))
        registry = WindowRegistry()
        parker = Parker(resolver: registry, store: store)
        switcher = Switcher(registry: registry, parker: parker, store: store, config: config)
        assigner = Assigner(switcher: switcher)

        // The UI is built BEFORE the registry starts. `start()` sweeps
        // immediately and fires onWindowAdded for every window already open,
        // and those callbacks reach refreshUI — which would find `mask` and
        // `menuBar` still nil and trap on the implicit unwrap. Starting the
        // registry is therefore the last thing this method does.
        mask = SliverMask()
        mask.show()

        menuBar = MenuBarController(switcher: switcher, parker: parker,
                                    tracker: tracker, config: config)
        menuBar.onSelectBox = { [weak self] box in self?.switchTo(box) }
        menuBar.onPanic = { [weak self] in
            self?.parker.unparkAll()
            self?.refreshUI()
        }
        menuBar.onQuit = { NSApp.terminate(nil) }
        menuBar.onReloadConfig = { [weak self] in self?.reloadConfig() }

        palette = PaletteWindow()
        menuBar.onOpenPalette = { [weak self] in self?.showPalette() }
        mask.onClick = { [weak self] in self?.showPalette() }
        hotKey = HotKey(spec: config.hotkey) { [weak self] in self?.showPalette() }
        if hotKey == nil {
            NSLog("kutu: could not register hotkey '\(config.hotkey)'")
        }

        switcher.onChange = { [weak self] in self?.refreshUI() }

        registry.onWindowAdded = { [weak self] ref in
            self?.assigner.windowAppeared(ref)
            self?.refreshUI()
        }
        registry.onWindowRemoved = { [weak self] id in
            self?.switcher.forget(id)
            self?.refreshUI()
        }

        activationGuard = ActivationGuard(registry: registry, parker: parker,
                                          switcher: switcher,
                                          pinnedBundleIDs: Set(config.pinnedBundleIDs))
        activationGuard.onWantsSwitch = { [weak self] box in self?.switchTo(box) }
        activationGuard.start()

        launcher = Launcher(assigner: assigner)
        statusServer = StatusServer(path: StatusServer.defaultPath) { [weak self] payload in
            self?.handle(payload)
        }
        do {
            try statusServer.start()
        } catch {
            NSLog("kutu: status socket unavailable: \(error)")
        }

        registry.start()

        registry.refresh()
        parker.reconcile(activeBox: switcher.activeBox,
                         membership: switcher.membership,
                         pinnedBundleIDs: Set(config.pinnedBundleIDs),
                         windows: registry.windows)

        // Terminate unparks everything, so the saved box's containment has to
        // be re-established or the UI claims a box while every window is
        // visible. Safe only because C1 no longer rewrites membership here.
        if switcher.activeBox != Membership.lobby {
            switchTo(switcher.activeBox)
        }

        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave a window the user cannot reach.
        parker?.unparkAll()
    }

    private func reloadConfig() {
        config = (try? KutuConfig.load(from: Self.configPath)) ?? KutuConfig()
        switcher.reload(config: config)
        menuBar.reload(config: config)
        activationGuard.reload(pinnedBundleIDs: Set(config.pinnedBundleIDs))
        hotKey?.unregister()
        hotKey = HotKey(spec: config.hotkey) { [weak self] in self?.showPalette() }
        if hotKey == nil {
            // Same diagnostic as the launch path. Without it, editing
            // boxes.toml to an unparseable or already-taken combination
            // silently leaves the user with no hotkey and no clue why.
            NSLog("kutu: could not register hotkey '\(config.hotkey)' after reload")
        }
        refreshUI()
    }

    private func switchTo(_ box: String) {
        switcher.switchTo(box)
        assigner.boxChanged(to: box)
        // Suppression starts AFTER the switch, not before. Parking and
        // unparking is synchronous Accessibility work that can take a
        // meaningful slice of a second under load; starting the clock first
        // spends the budget on the switch itself and can let the resulting
        // activation notification arrive unsuppressed. Workspace notifications
        // are posted to the main run loop, so anything fired during the switch
        // is still delivered after this line runs.
        activationGuard?.suppress(for: 1.0)
        refreshUI()
    }

    /// One socket carries both control commands and status reports. Control
    /// messages are the ones carrying a "kutu" key; everything else is offered
    /// to the status decoder, so third-party payloads need no wrapper.
    private func handle(_ payload: Data) {
        if let control = try? JSONDecoder().decode(ControlMessage.self, from: payload) {
            switch control.kutu {
            case "switch":
                if let box = control.arg { switchTo(box) }
                return
            case "open":
                guard let box = control.arg else { return }
                if let spec = config.boxes.first(where: { $0.name == box }) {
                    launcher.hydrate(box: spec)
                }
                switchTo(box)
                return
            case "panic":
                parker.unparkAll()
                refreshUI()
                return
            case "status":
                if control.state == nil, let box = control.arg {
                    tracker.clearAll(forBox: box,
                                     directory: config.boxes.first { $0.name == box }?.dir)
                    refreshUI()
                    return
                }
            default:
                break   // "status" falls through to the decoder below
            }
        }
        if let report = StatusDecoder.decode(payload) {
            tracker.apply(report)
            refreshUI()
        }
    }

    private func showPalette() {
        guard !palette.isVisible else {
            palette.dismiss()
            return
        }
        let counts = Dictionary(grouping: registry.windows) { window in
            switcher.membership.boxName(for: window,
                                        pinnedBundleIDs: Set(config.pinnedBundleIDs))
        }.mapValues(\.count)

        let rows = switcher.knownBoxes.map { box in
            PaletteRow(name: box,
                       state: tracker.state(forBox: box,
                                            directory: config.boxes.first { $0.name == box }?.dir),
                       windowCount: counts[box] ?? 0)
        }
        palette.present(boxes: rows) { [weak self] box in self?.switchTo(box) }
    }

    private func refreshUI() {
        // Registry callbacks can arrive before the UI exists and after it is
        // torn down, so this tolerates a half-built delegate rather than
        // relying on call ordering alone.
        guard let mask, let menuBar else { return }
        let box = switcher.activeBox
        mask.setLabel(box, state: tracker.state(forBox: box,
                                                directory: config.boxes.first { $0.name == box }?.dir))
        menuBar.refresh()
    }

    private func presentTrustAlert() {
        let alert = NSAlert()
        alert.messageText = "kutu needs Accessibility access"
        alert.informativeText = "Enable kutu in System Settings → Privacy & Security → Accessibility, then relaunch."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
