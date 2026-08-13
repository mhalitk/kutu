import AppKit
import KutuCore

public struct PaletteRow: Sendable, Equatable {
    public let name: String
    public let state: Status?
    public let windowCount: Int

    public init(name: String, state: Status?, windowCount: Int) {
        self.name = name
        self.state = state
        self.windowCount = windowCount
    }
}

/// A borderless window returns `canBecomeKey == false`, which would leave the
/// filter field unable to receive a single keystroke. Verified on this SDK.
/// `.nonactivatingPanel` is what lets it take keyboard input *without*
/// activating kutu, so overriding this keeps the palette usable while still
/// leaving the frontmost application untouched.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A non-activating overlay: showing it must not change which application is
/// frontmost, or the switch it triggers would land in the wrong place.
public final class PaletteWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: PalettePanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()

    private var allRows: [PaletteRow] = []
    private var rows: [PaletteRow] = []
    private var onPick: ((String) -> Void)?

    public override init() {
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()

        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        field.placeholderString = "Switch to box…"
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(field)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("box"))
        column.width = 420
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.target = self
        table.doubleAction = #selector(pickSelected)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8)
        ])
    }

    public func present(boxes: [PaletteRow], onPick: @escaping (String) -> Void) {
        self.allRows = boxes
        self.rows = boxes
        self.onPick = onPick
        field.stringValue = ""
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2 + 80))
        }
        // Key, not merely front: ordering a window forward does not give it
        // keyboard focus, and the palette is useless without it.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    public func dismiss() {
        panel.orderOut(nil)
    }

    public var isVisible: Bool { panel.isVisible }

    public func controlTextDidChange(_ notification: Notification) {
        let query = field.stringValue.lowercased()
        rows = query.isEmpty ? allRows : allRows.filter { Self.matches($0.name.lowercased(), query) }
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    /// Subsequence match, so "orc" finds "orchard" and "hc" finds "halit-ca".
    static func matches(_ candidate: String, _ query: String) -> Bool {
        var index = candidate.startIndex
        for character in query {
            guard let found = candidate[index...].firstIndex(of: character) else { return false }
            index = candidate.index(after: found)
        }
        return true
    }

    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            pickSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1)
            return true
        default:
            return false
        }
    }

    private func move(by delta: Int) {
        guard !rows.isEmpty else { return }
        let next = min(max(table.selectedRow + delta, 0), rows.count - 1)
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    @objc private func pickSelected() {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { return }
        let name = rows[table.selectedRow].name
        dismiss()
        onPick?(name)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        let entry = rows[row]
        let symbol: String
        switch entry.state {
        case .waiting: symbol = "🟡"
        case .working: symbol = "🔵"
        case .idle: symbol = "⚪️"
        case .none: symbol = "▫️"
        }
        let text = "\(symbol)  \(entry.name)"
        let detail = entry.windowCount == 1 ? "1 window" : "\(entry.windowCount) windows"

        let container = NSView()
        let title = NSTextField(labelWithString: text)
        title.font = .systemFont(ofSize: 14)
        let count = NSTextField(labelWithString: detail)
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        count.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        container.addSubview(count)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            count.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
