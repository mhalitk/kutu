import Foundation

public struct SwitchPlan: Sendable, Equatable {
    public let toPark: [WindowID]
    public let toUnpark: [WindowID]

    public init(toPark: [WindowID], toUnpark: [WindowID]) {
        self.toPark = toPark
        self.toUnpark = toUnpark
    }

    /// Splits every managed window into "must be visible" and "must be hidden"
    /// for the target box. Pinned and full-screen windows are always visible;
    /// full-screen windows because macOS gives them their own Space and they
    /// cannot be moved at all.
    public static func compute(all: [KutuWindow],
                               membership: Membership,
                               pinnedBundleIDs: Set<String>,
                               target: String) -> SwitchPlan {
        var park: [WindowID] = []
        var unpark: [WindowID] = []
        for ref in all {
            if ref.isFullScreen {
                unpark.append(ref.id)
                continue
            }
            switch membership.tier(of: ref, pinnedBundleIDs: pinnedBundleIDs) {
            case .pinned:
                unpark.append(ref.id)
            case .boxed(let box):
                if box == target { unpark.append(ref.id) } else { park.append(ref.id) }
            case .loose:
                if target == Membership.lobby { unpark.append(ref.id) } else { park.append(ref.id) }
            }
        }
        return SwitchPlan(toPark: park, toUnpark: unpark)
    }
}
