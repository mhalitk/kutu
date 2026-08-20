import CoreGraphics

/// Pure geometry for reasoning about where windows actually land, never about
/// where a particular display arrangement is expected to put them. macOS's
/// clamp on an out-of-range Accessibility position already guarantees a
/// parked window stays reachable on *some* screen; which screen and which
/// corner depends on the current arrangement and can change at any time. So
/// this module never predicts an arrangement — callers park, then read back
/// the resulting frame and hand it here.
public enum Geometry {
    /// The parts of `frames` that actually fall on a screen, unioned into one
    /// rect. nil when none of them are visible anywhere.
    public static func visibleUnion(of frames: [CGRect], screens: [CGRect]) -> CGRect? {
        var union: CGRect?
        for frame in frames {
            for screen in screens {
                let visible = frame.intersection(screen)
                guard !visible.isNull, !visible.isEmpty else { continue }
                union = union?.union(visible) ?? visible
            }
        }
        return union
    }

    /// A frame guaranteed to intersect a screen. Returns `frame` unchanged when
    /// it already does; otherwise moves it onto the screen nearest its origin,
    /// shrinking it if it is larger than that screen.
    public static func reachable(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard !screens.isEmpty else { return frame }
        if screens.contains(where: { !$0.intersection(frame).isNull && !$0.intersection(frame).isEmpty }) {
            return frame
        }

        let nearest = screens.min { lhs, rhs in
            distance(from: frame.origin, to: lhs) < distance(from: frame.origin, to: rhs)
        }!

        var result = frame
        result.size.width = min(result.width, nearest.width)
        result.size.height = min(result.height, nearest.height)
        result.origin.x = min(max(result.origin.x, nearest.minX), nearest.maxX - result.width)
        result.origin.y = min(max(result.origin.y, nearest.minY), nearest.maxY - result.height)
        return result
    }

    /// Straight-line distance from a point to the nearest point on a rect
    /// (zero when the point is inside it).
    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Whether a frame looks like a window that is already parked rather than
    /// one the user positioned. macOS clamps a parked window to a desktop
    /// corner leaving only a sliver on screen, so a frame whose origin sits
    /// within `tolerance` of any screen's far edge is not a position worth
    /// restoring to.
    ///
    /// Both axes are checked with `or`, not `and`: the clamp leaves a
    /// window's title bar height visible, and that height varies per app, so
    /// only one axis may sit exactly at the extreme while the other is
    /// merely near it.
    public static func looksParked(_ frame: CGRect, screens: [CGRect], tolerance: CGFloat = 48) -> Bool {
        guard !screens.isEmpty else { return false }
        for screen in screens {
            if frame.origin.x >= screen.maxX - tolerance || frame.origin.y >= screen.maxY - tolerance {
                return true
            }
        }
        return false
    }

    /// Side length for the kutu mark drawn inside a lid of `size`, or nil when
    /// the lid is too small to show it legibly. The mask is sized to whatever
    /// fragment macOS left on screen, which varies with the app's title bar, so
    /// the mark has to scale with it rather than assume room is available.
    public static func markSide(fitting size: CGSize,
                                maximum: CGFloat = 28,
                                minimum: CGFloat = 10,
                                fraction: CGFloat = 0.6) -> CGFloat? {
        let smaller = min(size.width, size.height)
        guard smaller > 0 else { return nil }
        let side = min(maximum, smaller * fraction)
        return side >= minimum ? side : nil
    }

    /// A reasonable on-screen frame for a window whose real position is
    /// unknown. Sized to `size`, shrunk to fit if larger than the screen, and
    /// placed a little inside the first screen's top-left rather than centred,
    /// so several rescued windows do not land exactly on top of each other.
    public static func defaultFrame(forSize size: CGSize, screens: [CGRect]) -> CGRect {
        guard let screen = screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        let inset: CGFloat = 40
        let x = min(screen.minX + inset, screen.maxX - width)
        let y = min(screen.minY + inset, screen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
