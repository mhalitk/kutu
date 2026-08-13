import Foundation
import CoreGraphics

public struct PersistedState: Sendable, Codable, Equatable {
    public var membership: Membership
    /// Window id (stringified) -> the frame the window had before it was parked.
    public var parkedFrames: [String: CGRect]
    public var activeBox: String

    public init(membership: Membership = Membership(),
                parkedFrames: [String: CGRect] = [:],
                activeBox: String = Membership.lobby) {
        self.membership = membership
        self.parkedFrames = parkedFrames
        self.activeBox = activeBox
    }
}

public struct StateFile: Sendable {
    private let path: String

    public init(path: String) {
        self.path = path
    }

    public static var defaultPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/state/kutu/state.json")
    }

    /// Never throws: a missing or corrupt state file must not stop kutu from
    /// starting, because starting is what lets the user unpark their windows.
    public func load() -> PersistedState {
        guard let data = FileManager.default.contents(atPath: path),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    public func save(_ state: PersistedState) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

/// The single owner of persisted state. Every component mutates through this,
/// so writes compose instead of overwriting one another.
public final class StateStore: @unchecked Sendable {
    private let file: StateFile
    private var state: PersistedState
    private let lock = NSLock()

    public init(file: StateFile) {
        self.file = file
        self.state = file.load()
    }

    public func snapshot() -> PersistedState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public var membership: Membership { snapshot().membership }
    public var activeBox: String { snapshot().activeBox }
    public var parkedFrames: [String: CGRect] { snapshot().parkedFrames }

    public func mutate(_ body: (inout PersistedState) -> Void) {
        lock.lock()
        body(&state)
        let copy = state
        lock.unlock()
        try? file.save(copy)
    }
}
