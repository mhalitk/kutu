import AppKit
import KutuCore

/// Covers the fragment macOS refuses to move off-screen. Nothing more: it is
/// sized to exactly the rect it was asked to cover, so it never occupies a
/// pixel the parked window does not already occupy. An earlier version padded
/// itself out to a labelled chip, which looked better but swallowed clicks in
/// screen area that had nothing to do with parking. The active box and the
/// parked count live in the menu bar, which is visible whether or not anything
/// is parked.
public final class SliverMask {
    public var onClick: (() -> Void)?

    private let panel: NSPanel
    /// Last rect passed to `cover(_:)`, kept so the panel can be re-framed
    /// without the caller having to pass it again.
    private var coveredRect: NSRect?
    private let scrim = NSView()

    public init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
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
        // Square, deliberately. A corner radius makes the four corners
        // transparent, and on a panel sized exactly to what it hides that
        // leaks the parked window through at every corner. Rounding was only
        // safe while the panel was padded far beyond the rect it covered.
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        scrim.wantsLayer = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scrim, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: effect.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: effect.trailingAnchor)
        ])
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            scrim.layer?.backgroundColor =
                NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        effect.addGestureRecognizer(click)
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    /// Positions the panel over exactly `rect`. `rect` is the union of the
    /// actual on-screen fragments, read back after parking rather than
    /// predicted from screen geometry, so this is correct for any display
    /// arrangement without knowing what it is.
    public func cover(_ rect: NSRect) {
        coveredRect = rect
        reposition()
    }

    private func reposition() {
        guard let rect = coveredRect else { return }
        panel.setFrame(rect, display: true)
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

    @objc private func clicked() {
        onClick?()
    }
}
