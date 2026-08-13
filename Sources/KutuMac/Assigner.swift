import Foundation
import KutuCore

/// Decides which box a newly created window belongs to. A window that appears
/// shortly after kutu launched an application is attributed to the box that
/// launched it; anything else joins whichever box is active.
public final class Assigner {
    private let switcher: Switcher
    private var claimBox: String?
    private var claimExpiry: Date = .distantPast

    public init(switcher: Switcher) {
        self.switcher = switcher
    }

    public func claimNextWindows(for box: String, seconds: TimeInterval = 10) {
        claimBox = box
        claimExpiry = Date().addingTimeInterval(seconds)
    }

    public func windowAppeared(_ ref: KutuWindow) {
        if let box = claimBox, Date() < claimExpiry {
            switcher.assign(ref.id, to: box)
            return
        }
        claimBox = nil
        let active = switcher.activeBox
        guard active != Membership.lobby else { return }  // lobby holds loose windows by definition
        switcher.assign(ref.id, to: active)
    }
}
