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
    private let tracker = StatusTracker()
    private var config = KutuConfig()

    static let configPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".config/kutu/boxes.toml")

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

        registry.onWindowAdded = { [weak self] ref in
            self?.assigner.windowAppeared(ref)
            self?.refreshUI()
        }
        registry.onWindowRemoved = { [weak self] id in
            self?.switcher.forget(id)
            self?.refreshUI()
        }
        registry.start()

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

        switcher.onChange = { [weak self] in self?.refreshUI() }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave a window the user cannot reach.
        parker?.unparkAll()
    }

    private func switchTo(_ box: String) {
        switcher.switchTo(box)
        refreshUI()
    }

    private func refreshUI() {
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
