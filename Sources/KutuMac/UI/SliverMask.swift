import AppKit
import KutuCore

/// Covers the fragment macOS refuses to move off-screen, and doubles as the
/// always-visible indicator of which box is active.
public final class SliverMask {
    public var onClick: (() -> Void)?

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

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

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(dot)

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        effect.addGestureRecognizer(click)
    }

    public func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func setLabel(_ text: String, state: Status?) {
        label.stringValue = text
        dot.layer?.backgroundColor = Self.color(for: state).cgColor
        reposition()
    }

    /// Anchored to the bottom-right of the main screen, which is exactly where
    /// macOS clamps a window parked at (60000, 60000).
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let width = max(Self.minWidth, label.intrinsicContentSize.width + 44)
        let frame = NSRect(x: screen.frame.maxX - width,
                           y: screen.frame.minY,
                           width: width,
                           height: Self.height)
        panel.setFrame(frame, display: true)
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
