import AppKit
import KutuCore

/// Covers the fragments macOS refuses to move off-screen. Nothing more: each
/// lid is sized to exactly the fragment it was asked to cover, so it never
/// occupies a pixel a parked window does not already occupy. An earlier
/// version padded itself out to a labelled chip, which looked better but
/// swallowed clicks in screen area that had nothing to do with parking. The
/// active box and the parked count live in the menu bar, which is visible
/// whether or not anything is parked.
///
/// One lid per fragment rather than one over all of them: parked windows can
/// land at different heights or on different displays, and a single panel
/// spanning them covers the desktop in between.
public final class SliverMask {
    public var onClick: (() -> Void)?

    private var lids: [Lid] = []
    private var isShown = false

    public init() {}

    public func show() {
        isShown = true
        lids.forEach { $0.panel.orderFrontRegardless() }
    }

    public func hide() {
        isShown = false
        lids.forEach { $0.panel.orderOut(nil) }
    }

    /// Positions one lid over exactly each of `rects`. They are the actual
    /// on-screen fragments, read back after parking rather than predicted from
    /// screen geometry, so this is correct for any display arrangement without
    /// knowing what it is. Lids are reused across calls and surplus ones
    /// retired, so a switch does not churn panels.
    public func cover(_ rects: [NSRect]) {
        while lids.count < rects.count {
            let lid = Lid()
            lid.onClick = { [weak self] in self?.onClick?() }
            lids.append(lid)
        }
        while lids.count > rects.count {
            lids.removeLast().panel.orderOut(nil)
        }
        for (lid, rect) in zip(lids, rects) {
            lid.cover(rect)
            if isShown { lid.panel.orderFrontRegardless() }
        }
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

}

/// A single panel over a single fragment.
private final class Lid {
    var onClick: (() -> Void)?

    let panel: NSPanel
    private lazy var markSide = mark.widthAnchor.constraint(equalToConstant: 0)
    private lazy var markHeight = mark.heightAnchor.constraint(equalToConstant: 0)
    private let scrim = NSView()
    private let mark = NSImageView()

    init() {
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

        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.contentTintColor = .secondaryLabelColor
        mark.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            markSide, markHeight
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        effect.addGestureRecognizer(click)
    }

    /// The mark scales with the lid and disappears entirely when the fragment
    /// is too small to show it — the lid's job is to cover, and identifying
    /// itself is secondary to that.
    func cover(_ rect: NSRect) {
        panel.setFrame(rect, display: true)

        if let side = Geometry.markSide(fitting: rect.size) {
            mark.image = KutuMark.templateImage(side: side)
            mark.isHidden = false
            markSide.constant = side
            markHeight.constant = side
        } else {
            mark.isHidden = true
        }
    }

    @objc private func clicked() {
        onClick?()
    }
}
