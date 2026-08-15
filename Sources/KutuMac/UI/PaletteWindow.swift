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

/// kutu's signature element: a small drawn square whose fill carries a box's
/// status. Selection is a separate affordance (drawn by `PaletteRowView`), so
/// this view only ever renders `state` — it has no notion of being selected.
final class StatusSquareView: NSView {
    var state: Status? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Inset by half the stroke width so a 1.5pt outline doesn't clip
        // against the view's own bounds.
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)

        switch state {
        case .working:
            NSColor.systemBlue.setFill()
            path.fill()
        case .waiting:
            NSColor.systemOrange.setFill()
            path.fill()
        case .idle:
            path.lineWidth = 1.5
            NSColor.tertiaryLabelColor.setStroke()
            path.stroke()
        case .none:
            path.lineWidth = 1.5
            NSColor.quaternaryLabelColor.setStroke()
            path.stroke()
        }
    }
}

/// Draws its own selection instead of the table's default full-bleed grey
/// highlight, since the table's `selectionHighlightStyle` is set to `.none`.
final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(dx: 8, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
    }
}

/// A non-activating overlay: showing it must not change which application is
/// frontmost, or the switch it triggers would land in the wrong place.
public final class PaletteWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: PalettePanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyContainer = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No box matches")

    private var allRows: [PaletteRow] = []
    private var rows: [PaletteRow] = []
    private var onPick: ((String) -> Void)?

    private static let width: CGFloat = 460
    private static let headerHeight: CGFloat = 56
    private static let rowHeight: CGFloat = 32
    private static let bottomPadding: CGFloat = 8
    private static let maxVisibleRows = 7

    public override init() {
        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.headerHeight + Self.bottomPadding),
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

        field.placeholderString = "Go to box"
        field.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(field)

        let hairline = NSBox()
        hairline.boxType = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hairline)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("box"))
        column.width = Self.width
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.target = self
        table.doubleAction = #selector(pickSelected)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.isHidden = true
        emptyContainer.addSubview(emptyLabel)
        effect.addSubview(emptyContainer)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 18),
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),

            hairline.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 14),
            hairline.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: effect.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),

            emptyContainer.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 8),
            emptyContainer.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor)
        ])
    }

    public func present(boxes: [PaletteRow], onPick: @escaping (String) -> Void) {
        self.allRows = boxes
        self.rows = boxes
        self.onPick = onPick
        field.stringValue = ""
        layoutPanel()
        if !rows.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

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
        layoutPanel()
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

    /// Sizes the panel to its content — header plus rows, capped at
    /// `maxVisibleRows` before it scrolls — and re-centres it. Called on
    /// every `present` and whenever filtering changes the row set, so the
    /// palette never shows dead space or an unnecessary scroller.
    private func layoutPanel() {
        table.reloadData()

        let isEmpty = rows.isEmpty
        scroll.isHidden = isEmpty
        emptyContainer.isHidden = !isEmpty

        // An empty result still needs room to show the explanatory label;
        // borrow one row's worth of height for it.
        let visibleRowCount = isEmpty ? 1 : min(rows.count, Self.maxVisibleRows)
        let height = Self.headerHeight + CGFloat(visibleRowCount) * Self.rowHeight + Self.bottomPadding

        var frame = panel.frame
        frame.size = NSSize(width: Self.width, height: height)
        if let screen = NSScreen.main {
            frame.origin = NSPoint(
                x: screen.frame.midX - Self.width / 2,
                y: screen.frame.midY - height / 2 + 80)
        }
        panel.setFrame(frame, display: true)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("paletteRow")
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? PaletteRowView {
            return reused
        }
        let rowView = PaletteRowView()
        rowView.identifier = identifier
        return rowView
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                          row: Int) -> NSView? {
        let entry = rows[row]

        let container = NSView()

        let square = StatusSquareView()
        square.state = entry.state
        square.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: entry.name)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(square)
        container.addSubview(title)

        NSLayoutConstraint.activate([
            square.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            square.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            square.widthAnchor.constraint(equalToConstant: 10),
            square.heightAnchor.constraint(equalToConstant: 10),

            title.leadingAnchor.constraint(equalTo: square.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        // The count is noise when it's zero — a fresh box with no windows
        // doesn't need "0" next to its name — so it's only added when > 0.
        if entry.windowCount > 0 {
            let count = NSTextField(labelWithString: "\(entry.windowCount)")
            count.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            count.textColor = .tertiaryLabelColor
            count.alignment = .right
            count.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(count)
            NSLayoutConstraint.activate([
                count.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                count.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8)
            ])
        } else {
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16).isActive = true
        }

        return container
    }
}
