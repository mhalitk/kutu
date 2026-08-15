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

    /// Drops assignments for windows that no longer exist. Window ids come from
    /// the window server and are NOT stable across reboots, so without this the
    /// map grows without bound — and worse, a fresh window can inherit an id a
    /// previous session assigned to a box and be filed there silently.
    public mutating func prune(livingWindowIDs living: Set<WindowID>) {
        let alive = Set(living.map(String.init))
        boxed = boxed.filter { alive.contains($0.key) }
        pinnedWindows = pinnedWindows.intersection(alive)
    }

    /// Number of live entries, for diagnostics.
    public var assignmentCount: Int { boxed.count + pinnedWindows.count }

    public func tier(of ref: KutuWindow, pinnedBundleIDs: Set<String>) -> Tier {
        if pinnedWindows.contains(String(ref.id)) || pinnedBundleIDs.contains(ref.bundleID) {
            return .pinned
        }
        if let box = boxed[String(ref.id)] { return .boxed(box) }
        return .loose
    }

    /// The box a window is visible in. Loose windows live in the lobby.
    public func boxName(for ref: KutuWindow, pinnedBundleIDs: Set<String>) -> String {
        switch tier(of: ref, pinnedBundleIDs: pinnedBundleIDs) {
        case .boxed(let box): return box
        case .pinned: return Membership.lobby
        case .loose: return Membership.lobby
        }
    }

}
