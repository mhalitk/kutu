import AppKit

/// kutu's mark: three windows stacked back-to-front, the frontmost solid and
/// the ones behind it outlined — what a box actually is, one window in view
/// and the rest held behind it.
///
/// Drawn rather than shipped as an asset. The menu bar, the sliver mask and
/// the app icon all render from this one function, so the Dock icon cannot
/// drift from the mark in the UI, and the repo carries no binaries.
public enum KutuMark {
    /// Laid out on a 32pt grid and scaled, so every constant below can be read
    /// as "points at the reference size" instead of an opaque fraction.
    private static let grid: CGFloat = 32

    /// Below this the mark drops from three windows to two.
    private static let layerDropSide: CGFloat = 26

    /// Draws the mark filling `side` points, origin at (0, 0), in `color`.
    /// AppKit's y grows upward, so the frontmost window sits lowest and the
    /// stack recedes up and to the right.
    ///
    /// Three windows need roughly six separate one-pixel features stacked
    /// vertically — two strokes, two gutters, two gaps — which a menu bar's
    /// 18pt simply cannot resolve; below `layerDropSide` it collapses into a
    /// smudge. Small sizes therefore draw two windows, which still reads as a
    /// stack and stays legible.
    ///
    /// `gutter` is what the separating channels are filled with: nil punches
    /// them out, which is what a template image needs, while a colour paints
    /// them. The app icon must pass its ground colour — punching there would
    /// cut transparent slots straight through the icon.
    public static func draw(side: CGFloat, color: NSColor, gutter: NSColor? = nil) {
        guard side > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let layers = side >= layerDropSide ? 3 : 2
        let unit = side / grid
        let radius = 2.5 * unit
        let lineWidth = max(1.25, 2 * unit)

        let window = CGSize(width: 20 * unit, height: 15 * unit)
        let step = 4.5 * unit
        let spread = step * CGFloat(layers - 1)
        // Centred as a whole, so the stack sits in the middle of the canvas
        // rather than the frontmost window doing so.
        let origin = CGPoint(x: (side - window.width - spread) / 2,
                             y: (side - window.height - spread) / 2)

        func rect(_ index: Int) -> CGRect {
            CGRect(x: origin.x + step * CGFloat(index),
                   y: origin.y + step * CGFloat(index),
                   width: window.width,
                   height: window.height)
        }

        color.setStroke()

        // Back to front, each window clearing a gutter out of whatever it
        // overlaps before drawing itself. Occlusion has to be punched rather
        // than painted: in a template image every pixel is the same colour, so
        // a nearer window can only separate itself from the one behind by
        // removing pixels, never by covering them in a lighter shade.
        for index in stride(from: layers - 1, through: 0, by: -1) {
            let frame = rect(index)
            let channel = NSBezierPath(roundedRect: frame.insetBy(dx: -lineWidth, dy: -lineWidth),
                                       xRadius: radius + lineWidth,
                                       yRadius: radius + lineWidth)
            if let gutter {
                gutter.setFill()
                channel.fill()
            } else {
                context.saveGState()
                context.setBlendMode(.clear)
                channel.fill()
                context.restoreGState()
            }

            color.setFill()
            if index == 0 {
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            } else {
                let path = NSBezierPath(roundedRect: frame.insetBy(dx: lineWidth / 2,
                                                                  dy: lineWidth / 2),
                                        xRadius: radius, yRadius: radius)
                path.lineWidth = lineWidth
                path.stroke()
            }
        }
    }

    /// A template image for the menu bar and the sliver mask. Template images
    /// are tinted by AppKit to suit the appearance and the menu bar's
    /// highlight state, so this must not carry a colour of its own.
    public static func templateImage(side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            draw(side: side, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The app icon: the mark on the rounded ground macOS expects, with the
    /// margin Apple's icon grid calls for so it does not look oversized beside
    /// other icons in Finder and system dialogs.
    public static func drawAppIcon(side: CGFloat) {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let inset = side * 0.08
        let ground = NSColor(calibratedRed: 0.043, green: 0.51, blue: 0.51, alpha: 1)
        ground.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                     xRadius: side * 0.22, yRadius: side * 0.22).fill()

        let markSide = side * 0.56
        let offset = (side - markSide) / 2
        NSGraphicsContext.current?.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: offset, yBy: offset)
        transform.concat()
        draw(side: markSide, color: .white, gutter: ground)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
