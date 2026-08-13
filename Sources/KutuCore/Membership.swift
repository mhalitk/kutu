import Foundation

/// Window-to-box assignment. Keys are stringified window ids so the persisted
/// JSON stays human-readable.
public struct Membership: Sendable, Codable, Equatable {
    public static let lobby = "lobby"

    private var boxed: [String: String]
    private var pinnedWindows: Set<String>

    public init(boxed: [String: String] = [:], pinnedWindows: Set<String> = []) {
        self.boxed = boxed
        self.pinnedWindows = pinnedWindows
    }

    public mutating func assign(_ id: WindowID, to box: String) {
        boxed[String(id)] = box
    }

    public mutating func pin(_ id: WindowID) {
        pinnedWindows.insert(String(id))
    }

    public mutating func unpin(_ id: WindowID) {
        pinnedWindows.remove(String(id))
    }

    public mutating func forget(_ id: WindowID) {
        boxed.removeValue(forKey: String(id))
        pinnedWindows.remove(String(id))
    }

    public func tier(of ref: WindowRef, pinnedBundleIDs: Set<String>) -> Tier {
        if pinnedWindows.contains(String(ref.id)) || pinnedBundleIDs.contains(ref.bundleID) {
            return .pinned
        }
        if let box = boxed[String(ref.id)] { return .boxed(box) }
        return .loose
    }

    /// The box a window is visible in. Loose windows live in the lobby.
    public func boxName(for ref: WindowRef, pinnedBundleIDs: Set<String>) -> String {
        switch tier(of: ref, pinnedBundleIDs: pinnedBundleIDs) {
        case .boxed(let box): return box
        case .pinned: return Membership.lobby
        case .loose: return Membership.lobby
        }
    }

}
