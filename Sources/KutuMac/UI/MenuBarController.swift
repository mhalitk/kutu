import AppKit
import KutuCore

public final class MenuBarController: NSObject, NSMenuDelegate {
    public var onSelectBox: ((String) -> Void)?
    public var onPanic: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onOpenPalette: (() -> Void)?
    public var onReloadConfig: (() -> Void)?

    private let statusItem: NSStatusItem
    private let switcher: Switcher
    private let parker: Parker
    private let tracker: StatusTracker
    private var config: KutuConfig

    public init(switcher: Switcher, parker: Parker, tracker: StatusTracker, config: KutuConfig) {
        self.switcher = switcher
        self.parker = parker
        self.tracker = tracker
        self.config = config
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    public func reload(config: KutuConfig) {
        self.config = config
        refresh()
    }

    /// Shows `text` in place of the usual title until the next `refresh()`.
    /// The caller owns the restore: every path that changes what the title
    /// should say already ends in `refresh()`, so a hint survives exactly as
    /// long as nothing more important happens — which is the behaviour the
    /// mask had when it carried these messages.
    public func flash(_ text: String) {
        statusItem.button?.title = "▣ \(text)"
    }

    public func refresh() {
        let needsAttention = boxesNeedingAttention()
        let title = needsAttention.isEmpty
            ? "▣ \(switcher.activeBox)"
            : "▣ \(switcher.activeBox) ●\(needsAttention.count)"
        statusItem.button?.title = title
    }

    private func boxesNeedingAttention() -> [String] {
        switcher.knownBoxes.filter { status(of: $0) == .waiting }
    }

    /// A box need not appear in the config to have a status: an ad-hoc box can
    /// still be reported on by name.
    private func status(of box: String) -> Status? {
        tracker.state(forBox: box, directory: config.boxes.first { $0.name == box }?.dir)
    }

    private func symbol(for box: String) -> String {
        switch status(of: box) {
        case .waiting: return "🟡"
        case .working: return "🔵"
        case .idle: return "⚪️"
        case .none: return "  "
        }
    }


    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        add(menu, "Open palette  ⌥Space", #selector(openPalette))
        menu.addItem(.separator())

        for box in switcher.knownBoxes {
            let item = NSMenuItem(title: "\(symbol(for: box)) \(box)",
                                  action: #selector(selectBox(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = box
            item.state = (box == switcher.activeBox) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if StageManagerGuard.isEnabled {
            add(menu, "⚠︎ Stage Manager is on — kutu cannot hide windows",
                #selector(openStageManagerSettings))
        }

        let parked = parker.parkedIDs.count
        add(menu, "Unpark everything (\(parked) hidden)", #selector(panic))
        add(menu, "Reload config", #selector(reloadConfig))
        add(menu, "Quit kutu", #selector(quit)).keyEquivalent = "q"
    }

    @objc private func selectBox(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? String else { return }
        onSelectBox?(box)
    }

    @objc private func openPalette() { onOpenPalette?() }
    @objc private func panic() { onPanic?() }
    @objc private func reloadConfig() { onReloadConfig?() }
    @objc private func quit() { onQuit?() }
    @objc private func openStageManagerSettings() { StageManagerGuard.openSettings() }

    /// AppKit already declares addItem(withTitle:action:keyEquivalent:), so this
    /// is a separate helper rather than an overload, which would not compile.
    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }
}
