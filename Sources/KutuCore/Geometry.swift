import CoreGraphics

public enum Geometry {
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
}
