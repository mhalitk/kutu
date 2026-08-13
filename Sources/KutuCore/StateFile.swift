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
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public static var defaultPath: String { KutuPaths.stateFile }

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

    /// The lock is deliberately held across the file write, not just the
    /// in-memory mutation. Releasing it first lets two writers' saves race, so
    /// an earlier, smaller snapshot can land on disk after a later one and
    /// silently drop a mutation — and a dropped parked-frame is a window the
    /// user cannot reach. The file is a few hundred bytes; correctness wins.
    ///
    /// `body` runs under the lock, so it must not call back into this store.
    @discardableResult
    public func mutate(_ body: (inout PersistedState) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        body(&state)
        do {
            try file.save(state)
            return true
        } catch {
            NSLog("kutu: could not persist state to \(file.path): \(error)")
            return false
        }
    }
}
