import AppKit
import KutuCore

public struct PaletteRow: Sendable, Equatable {
    public let name: String
    public let state: Status?
    /// Faces of the apps whose windows live in this box, deduped by bundle
    /// identifier and capped at 5 — see `overflow` for the rest.
    public let icons: [NSImage]
    /// Count of distinct apps beyond the first 5 shown in `icons`.
    public let overflow: Int
    /// The box you are in right now. Marked with a leading caret rather than
    /// a background wash, so it reads at a glance without competing with the
    /// selection highlight.
    public let isActive: Bool

    public init(name: String, state: Status?, icons: [NSImage], overflow: Int, isActive: Bool = false) {
        self.name = name
        self.state = state
        self.icons = icons
        self.overflow = overflow
        self.isActive = isActive
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

/// Draws its own selection instead of the table's default full-bleed grey
/// highlight, replacing what AppKit would otherwise draw for `.regular`.
final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        rowRect().fill()
    }

    /// AppKit's "emphasized" selection (the window is key, so the highlight
    /// gets the system's own full-width blue treatment) draws *underneath*
    /// `drawSelection` and can still show through around it. Forcing this to
    /// `false` keeps the only selection paint the pill drawn above.
    override var isEmphasized: Bool {
        get { false }
        set { }
    }

    /// Inset so the fill reads as a pill inside the panel rather than a bar
    /// running edge to edge.
    private func rowRect() -> NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 6, yRadius: 6)
    }
}

/// A non-activating overlay: showing it must not change which application is
/// frontmost, or the switch it triggers would land in the wrong place.
public final class PaletteWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel: PalettePanel
    private let scrim = NSView()
    private var effect: NSVisualEffectView?
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyContainer = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No box matches")

    private var allRows: [PaletteRow] = []
    private var rows: [PaletteRow] = []
    private var onPick: ((String) -> Void)?

    /// Installed only while the palette is on screen. A monitor left running
    /// after dismissal would swallow every digit keystroke typed anywhere
    /// else, so it is torn down in `dismiss()` as carefully as it is set up
    /// in `present(boxes:onPick:)`.
    private var digitMonitor: Any?

    private static let width: CGFloat = 520
    private static let headerHeight: CGFloat = 56
    private static let rowHeight: CGFloat = 38
    private static let bottomPadding: CGFloat = 8
    private static let maxVisibleRows = 8

    /// Fixed x-position (from the row's leading edge) where a status word
    /// begins. Kept constant across every row — rather than trailing each
    /// name at whatever width it happens to render — so the words line up
    /// down the list regardless of name length.
    private static let statusColumnX: CGFloat = 210

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

        // `.hudWindow` is a DARK material: in Light mode it renders as
        // translucent grey and the desktop reads straight through, so the
        // panel's contrast depended on the user's wallpaper. `.popover` is
        // appearance-appropriate, and the scrim below makes legibility
        // unconditional — this window appears over terminals, browsers and
        // video, and must be readable over all of them.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        panel.contentView = effect

        // Near-opaque, semantic so it follows light/dark rather than pinning a
        // literal white that would invert badly at night. A little blur still
        // shows through at the edges, which keeps it feeling like a floating
        // panel rather than a flat rectangle.
        scrim.wantsLayer = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scrim, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: effect.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: effect.trailingAnchor)
        ])
        self.effect = effect

        field.placeholderString = "Go to box"
        field.font = .systemFont(ofSize: 15)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        // The placeholder inherits the field's text colour by default, which
        // would put it at full label strength — too loud for a hint whose job
        // is to recede behind the list.
        field.placeholderAttributedString = NSAttributedString(
            string: "Go to box",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 15)])
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
        // NOT `.none`: that disables AppKit's selection-drawing pipeline
        // entirely, including PaletteRowView's `drawSelection` override, so the
        // selection moves invisibly and the palette looks like it has stopped
        // responding to the arrow keys. `.regular` keeps the pipeline alive;
        // the override replaces what it draws.
        table.selectionHighlightStyle = .regular
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
        applyChrome()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        installDigitMonitor()
    }

    /// CGColors do not follow appearance changes on their own, so the scrim and
    /// border are resolved against the current appearance each time the palette
    /// is shown. It is rebuilt on every present anyway, so this costs nothing.
    private func applyChrome() {
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            scrim.layer?.backgroundColor =
                NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            effect?.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    public func dismiss() {
        panel.orderOut(nil)
        removeDigitMonitor()
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

    /// Picks and switches to the row at `index` directly — the same terminal
    /// action as `pickSelected()`, just addressed by row index instead of the
    /// table's current selection, so a digit press doesn't have to move the
    /// selection first.
    private func pick(rowAt index: Int) {
        guard index >= 0, index < rows.count else { return }
        let name = rows[index].name
        dismiss()
        onPick?(name)
    }

    /// 1–9 jump straight to a row and switch, with no Enter required — the
    /// interaction the whole layout is built around. Only live while the
    /// palette is on screen and only while the filter field is empty: once
    /// the user has typed letters, digits must fall through as normal query
    /// text instead of being hijacked as shortcuts.
    private func installDigitMonitor() {
        removeDigitMonitor()
        digitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.field.stringValue.isEmpty,
                  let characters = event.charactersIgnoringModifiers,
                  characters.count == 1,
                  let digit = characters.first,
                  let value = digit.wholeNumberValue,
                  (1...9).contains(value),
                  value <= self.rows.count
            else {
                return event
            }
            self.pick(rowAt: value - 1)
            return nil
        }
    }

    private func removeDigitMonitor() {
        if let digitMonitor {
            NSEvent.removeMonitor(digitMonitor)
        }
        digitMonitor = nil
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

        // 1. Shortcut numeral — right-aligned in a fixed gutter. Rows past
        // the 9th digit shortcut get nothing here.
        let numeralGutter = NSTextField(labelWithString: row < 9 ? "\(row + 1)" : "")
        numeralGutter.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        numeralGutter.textColor = .tertiaryLabelColor
        numeralGutter.alignment = .right
        numeralGutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(numeralGutter)

        // 2. Current-box caret — replaces the old background wash entirely.
        let caret = NSTextField(labelWithString: entry.isActive ? "▸" : "")
        caret.font = .systemFont(ofSize: 10)
        caret.textColor = .secondaryLabelColor
        caret.alignment = .center
        caret.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(caret)

        // 3. Box name.
        let title = NSTextField(labelWithString: entry.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        NSLayoutConstraint.activate([
            numeralGutter.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            numeralGutter.widthAnchor.constraint(equalToConstant: 20),
            numeralGutter.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            caret.leadingAnchor.constraint(equalTo: numeralGutter.trailingAnchor),
            caret.widthAnchor.constraint(equalToConstant: 12),
            caret.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: caret.trailingAnchor),
            title.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        // 5. App icons — deduplicated, capped, right-aligned. Built first (but
        // added last, so it draws above nothing in particular — order here
        // only matters for the trailing anchor the name and status lean on).
        let iconsStack = NSStackView()
        iconsStack.orientation = .horizontal
        iconsStack.spacing = 4
        iconsStack.alignment = .centerY
        iconsStack.translatesAutoresizingMaskIntoConstraints = false
        for icon in entry.icons {
            let imageView = NSImageView()
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 16).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 16).isActive = true
            iconsStack.addArrangedSubview(imageView)
        }
        if entry.overflow > 0 {
            let overflow = NSTextField(labelWithString: "+\(entry.overflow)")
            overflow.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            overflow.textColor = .tertiaryLabelColor
            iconsStack.addArrangedSubview(overflow)
        }
        container.addSubview(iconsStack)
        NSLayoutConstraint.activate([
            iconsStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            iconsStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: iconsStack.leadingAnchor, constant: -12)
        ])

        // 4. Status — dot plus lowercase word, only when the box has one.
        // `idle` renders nothing at all, same as no status.
        if let word = Self.statusWord(for: entry.state) {
            let color = entry.state == .waiting ? NSColor.systemOrange : NSColor.secondaryLabelColor

            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.cornerRadius = 3.5
            dot.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: word)
            label.font = .systemFont(ofSize: 11)
            label.textColor = color
            label.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(dot)
            container.addSubview(label)

            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.statusColumnX),
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7),
                dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: iconsStack.leadingAnchor, constant: -12),

                title.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -12)
            ])
        }

        return container
    }

    /// `idle` and no status at all are the same fact visually: nothing to
    /// show. Only `waiting` and `working` render.
    private static func statusWord(for state: Status?) -> String? {
        switch state {
        case .waiting: return "waiting"
        case .working: return "working"
        case .idle, .none: return nil
        }
    }
}
