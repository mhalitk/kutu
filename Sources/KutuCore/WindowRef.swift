import Foundation

public typealias WindowID = UInt32

public struct WindowRef: Sendable, Identifiable {
    public let id: WindowID
    public let pid: pid_t
    public let bundleID: String
    public let appName: String
    public let title: String
    public let frame: CGRect
    public let isFullScreen: Bool

    public init(id: WindowID, pid: pid_t, bundleID: String, appName: String,
                title: String, frame: CGRect, isFullScreen: Bool) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isFullScreen = isFullScreen
    }
}

public enum Tier: Sendable, Equatable {
    case boxed(String)
    case pinned
    case loose
}
