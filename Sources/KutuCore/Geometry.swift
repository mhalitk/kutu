import CoreGraphics

/// Pure geometry for reasoning about where windows actually land, never about
/// where a particular display arrangement is expected to put them. macOS's
/// clamp on an out-of-range Accessibility position already guarantees a
/// parked window stays reachable on *some* screen; which screen and which
/// corner depends on the current arrangement and can change at any time. So
/// this module never predicts an arrangement — callers park, then read back
/// the resulting frame and hand it here.
public enum Geometry {
    /// The parts of `frames` that actually fall on a screen, one rect per
    /// separate region. Fragments that overlap are merged, but disjoint ones
    /// are kept apart: parked windows can land at different heights or on
    /// different displays, and a single bounding rect over all of them would
    /// cover the desktop in between. Empty when nothing is visible anywhere.
    public static func visibleFragments(of frames: [CGRect], screens: [CGRect]) -> [CGRect] {
        var fragments: [CGRect] = []
        for frame in frames {
            for screen in screens {
                var piece = frame.intersection(screen)
                guard !piece.isNull, !piece.isEmpty else { continue }
                // Absorbing one fragment can make the grown rect reach another,
                // so keep merging until nothing left overlaps it.
                while let index = fragments.firstIndex(where: { $0.intersects(piece) }) {
                    piece = piece.union(fragments.remove(at: index))
                }
                fragments.append(piece)
            }
        }
        return fragments
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
    /// one the user positioned. macOS clamps a parked window so only a sliver
    /// of it stays on screen, so a frame is parked when no part of it visible
    /// on any screen is wider and taller than `tolerance` — including when
    /// nothing of it is visible at all.
    ///
    /// Judged by what is visible, not by where the origin sits relative to
    /// screen edges: with several displays, the far edge of one screen is the
    /// middle of the desktop, and an origin test there flags ordinary windows
    /// on the neighbouring display as parked. `frame` and `screens` must be in
    /// the same coordinate space.
    public static func looksParked(_ frame: CGRect, screens: [CGRect], tolerance: CGFloat = 48) -> Bool {
        guard !screens.isEmpty else { return false }
        return !visibleFragments(of: [frame], screens: screens).contains {
            $0.width > tolerance && $0.height > tolerance
        }
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
