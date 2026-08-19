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
}
