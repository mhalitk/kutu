import AppKit
import KutuCore

/// Covers the fragment macOS refuses to move off-screen, and doubles as the
/// active-box label. Only shown while something is actually parked; the menu
/// bar item is the persistent indicator when nothing needs covering.
public final class SliverMask {
    public var onClick: (() -> Void)?

    private let panel: NSPanel
    /// Last rect passed to `cover(_:)`. Kept so `setLabel` can re-run
    /// `reposition()` (the label's width can change the panel's width)
    /// without needing the caller to pass the rect again.
    private var coveredRect: NSRect?
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let scrim = NSView()
    private var effect: NSVisualEffectView?

    /// Tall enough for the largest observed title bar (64px) plus padding;
    /// wide enough to bury the 40px horizontal clamp under real content.
    private static let height: CGFloat = 72
    private static let minWidth: CGFloat = 132

    public init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false

        // Same treatment as the palette: `.hudWindow` is a DARK material and
        // rendered as a murky blob in Light mode, letting the desktop through.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        panel.contentView = effect
        self.effect = effect

        scrim.wantsLayer = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scrim, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: effect.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: effect.trailingAnchor)
        ])

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dot)

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        // This panel only exists while windows are parked, so it can answer the
        // one question you cannot get anywhere else at that moment: how much is
        // out of sight. Monospace so the number does not reflow as it changes.
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        detail.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(detail)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 20),

            detail.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -14),
            detail.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        effect.addGestureRecognizer(click)
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// Positions the panel over `rect` — anchored to its bottom-right corner,
    /// sized at least the panel's usual minimum, never smaller than `rect`
    /// itself. `rect` is the union of the actual on-screen fragments, read
    /// back after parking rather than predicted from screen geometry, so this
    /// is correct for any display arrangement without knowing what it is.
    public func cover(_ rect: NSRect) {
        coveredRect = rect
        reposition()
    }

    public func setLabel(_ text: String, state: Status?, hidden: Int = 0) {
        label.stringValue = text
        detail.stringValue = hidden == 1 ? "1 hidden" : "\(hidden) hidden"
        detail.isHidden = hidden == 0
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = Self.color(for: state).cgColor
            scrim.layer?.backgroundColor =
                NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            effect?.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        reposition()
    }

    /// Anchored to the bottom-right corner of the last-covered rect — that
    /// corner, not the screen's, because the covered rect is itself already
    /// wherever macOS actually clamped the parked fragments, on whichever
    /// screen that turned out to be.
    private func reposition() {
        guard let rect = coveredRect else { return }
        let width = max(Self.minWidth, rect.width, label.intrinsicContentSize.width + 44)
        let height = max(Self.height, rect.height)
        let frame = NSRect(x: rect.maxX - width,
                           y: rect.minY,
                           width: width,
                           height: height)
        panel.setFrame(frame, display: true)
    }

    /// Accessibility reports a top-left origin with y growing downward; AppKit
    /// windows use a bottom-left origin with y growing upward, both relative to
    /// the primary screen. Converting in one place keeps the mistake findable.
    public static func appKitRect(fromAccessibility rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            return rect
        }
        let y = primary.frame.height - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    /// The same flip, run the other way, for callers that need to hand AppKit
    /// geometry (e.g. `NSScreen.frame`) to code that talks to Accessibility —
    /// `Parker`, restoring a saved AX-space frame, needs the *screens* in
    /// that same space to compare against it. Spelled out as its own function
    /// rather than leaned on being its own inverse, so the direction at each
    /// call site stays obvious.
    public static func accessibilityRect(fromAppKit rect: NSRect) -> CGRect {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            return rect
        }
        let y = primary.frame.height - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    private static func color(for state: Status?) -> NSColor {
        switch state {
        case .waiting: return .systemYellow
        case .working: return .systemBlue
        case .idle, .none: return .tertiaryLabelColor
        }
    }

    @objc private func clicked() {
        onClick?()
    }
}
