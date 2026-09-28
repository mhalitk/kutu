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
    private var moveHotKey: HotKey?
    private var statusServer: StatusServer!
    private var launcher: Launcher!
    private let tracker = StatusTracker()
    private var config = KutuConfig()
    /// Bumped on every flashHint call so a stale, already-scheduled restore
    /// from an earlier hint cannot clobber a later one.
    private var hintGeneration = 0

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
        moveHotKey = HotKey(spec: config.moveHotkey) { [weak self] in self?.showMovePalette() }
        if moveHotKey == nil {
            NSLog("kutu: could not register move hotkey '\(config.moveHotkey)'")
        }

        // Parked windows sit at a fixed corner (Parker.parkPoint); attaching,
        // detaching, or rearranging a display can move that corner from past
        // every screen's edge to INSIDE the new arrangement, which un-clamps
        // whatever macOS was hiding there and makes hidden windows reappear.
        // Re-parking pushes them back out to wherever the new arrangement
        // clamps (60000, 60000) to. Do not delete this as redundant with a
        // manual park/unpark — nothing else exercises this path.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenParametersChanged()
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
        activationGuard.onActivatedHiddenApp = { [weak self] appName, box in
            guard let self else { return }
            switch self.config.cmdTab {
            case .switch:
                self.switchTo(box)
            case .notify:
                self.flashHint("\(appName) is in \(box)")
            }
        }
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
        switcher.pruneDeadAssignments()

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
        moveHotKey?.unregister()
        moveHotKey = HotKey(spec: config.moveHotkey) { [weak self] in self?.showMovePalette() }
        if moveHotKey == nil {
            NSLog("kutu: could not register move hotkey '\(config.moveHotkey)' after reload")
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
            case "reload":
                reloadConfig()
                return
            case "move":
                guard let box = control.arg else { return }
                guard let focused = resolveFocusedWindow() else {
                    flashHint("No window to move")
                    return
                }
                applyMove(.box(box), id: focused.id, currentBox: focused.currentBox)
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
        palette.present(moving: nil, boxes: boxRows()) { [weak self] choice in
            guard case .box(let box) = choice else { return }
            self?.switchTo(box)
        }
    }

    /// ⌥⇧Space: same panel as `showPalette`, but the destinations are read as
    /// "move the window I am looking at here" instead of "take me there".
    /// The subject is captured now, before the palette (non-activating, so
    /// this does not disturb it) ever appears — it is the only moment
    /// "frontmost application" reliably means the window the user meant.
    private func showMovePalette() {
        guard let focused = resolveFocusedWindow() else {
            flashHint("No window to move")
            return
        }
        let subject = PaletteSubject(appName: focused.appName, windowTitle: focused.title)
        palette.present(moving: subject, boxes: boxRows()) { [weak self] choice in
            self?.applyMove(choice, id: focused.id, currentBox: focused.currentBox)
        }
    }

    private struct FocusedWindow {
        let id: WindowID
        let appName: String
        let title: String
        let currentBox: String
    }

    /// The shared resolution behind both ⌥⇧Space and `kutu move`: the
    /// frontmost application (never kutu itself — the palette does not
    /// activate it, but a non-window surface like the trust alert can still
    /// be frontmost), its focused window as the window server knows it, and
    /// that window must already be one the registry has adopted.
    private func resolveFocusedWindow() -> FocusedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        guard let id = AXBridge.focusedWindowID(pid: app.processIdentifier) else { return nil }
        guard let window = registry.windows.first(where: { $0.id == id }) else { return nil }
        let title = window.title.isEmpty ? (app.localizedName ?? window.appName) : window.title
        let currentBox = switcher.membership.boxName(for: window,
                                                      pinnedBundleIDs: Set(config.pinnedBundleIDs))
        return FocusedWindow(id: id, appName: app.localizedName ?? window.appName,
                             title: title, currentBox: currentBox)
    }

    /// Applies one palette pick (or the CLI's equivalent) to the window
    /// resolved by `resolveFocusedWindow`, then re-parks immediately —
    /// `reapply()`, not `switchTo`, because the user is looking at this
    /// window and must not be yanked to another application over it.
    private func applyMove(_ choice: PaletteChoice, id: WindowID, currentBox: String) {
        switch choice {
        case .box(let name):
            guard name != currentBox else {
                flashHint("Already in \(name)")
                return
            }
            if name == Membership.lobby {
                switcher.forget(id)
            } else {
                switcher.assign(id, to: name)
            }
        case .pinEverywhere:
            switcher.pin(id)
        }
        switcher.reapply()
        refreshUI()
    }

    /// The box list the palette shows, in both "go to" and "move" mode —
    /// same rows, same ordering, same status and icons either way.
    private func boxRows() -> [PaletteRow] {
        let grouped = Dictionary(grouping: registry.windows) { window in
            switcher.membership.boxName(for: window,
                                        pinnedBundleIDs: Set(config.pinnedBundleIDs))
        }
        return switcher.knownBoxes.map { box -> PaletteRow in
            let (icons, overflow) = Self.faces(for: grouped[box] ?? [])
            return PaletteRow(name: box,
                       state: tracker.state(forBox: box,
                                            directory: config.boxes.first { $0.name == box }?.dir),
                       icons: icons,
                       overflow: overflow,
                       isActive: box == switcher.activeBox)
        }
    }

    /// The palette shows a box's apps, not its windows — several windows of
    /// the same app collapse to one face. Sorted by bundle identifier rather
    /// than by, say, most-recently-active, so the same box always shows the
    /// same icons in the same order between one ⌥Space and the next.
    private static func faces(for windows: [KutuWindow]) -> (icons: [NSImage], overflow: Int) {
        var iconsByBundleID: [String: NSImage] = [:]
        var seenBundleIDs = Set<String>()
        for window in windows where seenBundleIDs.insert(window.bundleID).inserted {
            if let icon = NSRunningApplication(processIdentifier: window.pid)?.icon {
                iconsByBundleID[window.bundleID] = icon
            }
        }
        let ordered = seenBundleIDs.sorted()
        let shown = ordered.prefix(5).compactMap { iconsByBundleID[$0] }
        let overflow = max(0, ordered.count - 5)
        return (shown, overflow)
    }

    private func refreshUI() {
        // Registry callbacks can arrive before the UI exists and after it is
        // torn down, so this tolerates a half-built delegate rather than
        // relying on call ordering alone.
        guard let mask, let menuBar else { return }

        // The mask exists to cover the fragments macOS leaves behind when a
        // window is parked. With nothing parked there is nothing to cover, so
        // showing it would be pure noise — the menu bar item is the persistent
        // indicator.
        if parker.parkedIDs.isEmpty {
            mask.hide()
        } else {
            repositionMask()
        }

        menuBar.refresh()
    }

    /// Where the mask goes: never predicted from the display arrangement,
    /// always read back from where macOS actually left the parked fragments.
    /// Refreshes the registry, resolves every parked id's current
    /// Accessibility frame (skipping ids that no longer resolve), converts
    /// each to AppKit coordinates, and covers each separate fragment of them
    /// that is actually visible on some screen. Hides the mask when there are
    /// none — nothing parked is currently visible anywhere.
    private func repositionMask() {
        guard let mask, let registry, let parker else { return }
        registry.refresh()
        let frames: [NSRect] = parker.parkedIDs.compactMap { id in
            guard let element = registry.element(for: id),
                  let position = AXBridge.position(element),
                  let size = AXBridge.size(element) else { return nil }
            return SliverMask.appKitRect(fromAccessibility: CGRect(origin: position, size: size))
        }
        let fragments = Geometry.visibleFragments(of: frames, screens: NSScreen.screens.map(\.frame))
        if !fragments.isEmpty {
            mask.cover(fragments)
            mask.show()
        } else {
            mask.hide()
        }
    }

    /// See the comment above the `didChangeScreenParametersNotification`
    /// observer in `applicationDidFinishLaunching` for why the re-park
    /// happens here rather than being treated as redundant.
    private func screenParametersChanged() {
        guard let registry, let parker else { return }
        for id in parker.parkedIDs {
            guard let element = registry.element(for: id) else { continue }
            AXBridge.setPosition(element, Parker.parkPoint)
        }
        repositionMask()
    }

    /// Briefly shows `text` in the menu bar title, then returns it to its
    /// normal state. A hint that arrives before the previous one expires replaces it
    /// and restarts the timer, rather than leaving a stale message or hiding
    /// early — `hintGeneration` lets the deferred restore recognise it has
    /// been superseded and no-op.
    private func flashHint(_ text: String) {
        hintGeneration += 1
        let generation = hintGeneration
        menuBar.flash(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.hintGeneration == generation else { return }
            self.refreshUI()
        }
    }

    private func presentTrustAlert() {
        let alert = NSAlert()
        alert.messageText = "kutu needs Accessibility access"
        // Ad-hoc builds change identity on every rebuild, which leaves behind a
        // stale entry that silently refuses to stay on — the switch reverts at
        // the next launch, and it reads as the grant simply not working.
        // Naming the reset here is the difference between a 10-second fix and
        // a dead end.
        let bundleID = Bundle.main.bundleIdentifier ?? "ca.halit.kutu"
        alert.informativeText = """
            Enable kutu in System Settings → Privacy & Security → Accessibility, then relaunch.

            After a rebuild, kutu may already be listed from the previous build. If the switch will not stay on, clear the old entry first:

            tccutil reset Accessibility \(bundleID)
            """
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
