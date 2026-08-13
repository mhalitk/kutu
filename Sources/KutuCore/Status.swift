// Sources/KutuCore/Status.swift
import Foundation

public enum Status: String, Sendable, Codable, CaseIterable {
    case working, waiting, idle

    /// Lower sorts first: the most demanding report wins when several things
    /// report on one box, so a box that needs you never looks quiet.
    var urgency: Int {
        switch self {
        case .waiting: return 0
        case .working: return 1
        case .idle: return 2
        }
    }
}

/// What a report is about. Directory scope exists because tools generally know
/// their working directory but not which box the user filed it under.
public enum StatusScope: Sendable, Equatable {
    case box(String)
    case directory(String)
}

public struct StatusReport: Sendable, Equatable {
    public let key: String
    public let scope: StatusScope
    /// nil retracts this reporter's status.
    public let state: Status?

    public init(key: String, scope: StatusScope, state: Status?) {
        self.key = key
        self.scope = scope
        self.state = state
    }
}

/// Commands sent to a running kutu over its socket, by the CLI or anything else.
public struct ControlMessage: Sendable, Codable, Equatable {
    public let kutu: String
    public let arg: String?
    public let state: String?
    public let key: String?

    public init(kutu: String, arg: String? = nil, state: String? = nil, key: String? = nil) {
        self.kutu = kutu
        self.arg = arg
        self.state = state
        self.key = key
    }
}

public enum StatusDecoder {
    /// Accepts either kutu's own status message or a third-party payload a known
    /// adapter understands. Supporting a new tool means adding an adapter here,
    /// never changing the tracker.
    public static func decode(_ data: Data) -> StatusReport? {
        if let control = try? JSONDecoder().decode(ControlMessage.self, from: data),
           control.kutu == "status", let box = control.arg {
            return StatusReport(key: control.key ?? "cli:\(box)",
                                scope: .box(box),
                                state: control.state.flatMap(Status.init(rawValue:)))
        }
        return claudeCodeHook(data)
    }

    /// Adapter for Claude Code's hook payload: one client of the channel, with
    /// no privileged position inside it.
    static func claudeCodeHook(_ data: Data) -> StatusReport? {
        struct Payload: Decodable {
            let hook_event_name: String
            let cwd: String
            let session_id: String
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let state: Status?
        switch payload.hook_event_name {
        case "UserPromptSubmit": state = .working
        case "Notification": state = .waiting
        case "Stop", "SubagentStop", "SessionStart": state = .idle
        case "SessionEnd": state = nil
        default: return nil
        }
        return StatusReport(key: payload.session_id,
                            scope: .directory(payload.cwd),
                            state: state)
    }
}

/// Live status of every reporter, aggregated per box.
public final class StatusTracker: @unchecked Sendable {
    private var reports: [String: StatusReport] = [:]
    private let lock = NSLock()

    public init() {}

    public func apply(_ report: StatusReport) {
        lock.lock()
        defer { lock.unlock() }
        if report.state == nil {
            reports.removeValue(forKey: report.key)
        } else {
            reports[report.key] = report
        }
    }

    public func clear(key: String) {
        lock.lock()
        defer { lock.unlock() }
        reports.removeValue(forKey: key)
    }

    /// Drops every report against a box, whatever reported it. The escape hatch
    /// for a reporter that died without retracting — a session killed with
    /// SIGKILL never sends its SessionEnd, and its status would otherwise pin
    /// the box lit until kutu restarts.
    public func clearAll(forBox name: String, directory: String?) {
        lock.lock()
        defer { lock.unlock() }
        let base = directory.map(Self.withoutTrailingSlash)
        reports = reports.filter { _, report in
            switch report.scope {
            case .box(let boxName):
                return boxName != name
            case .directory(let dir):
                guard let base else { return true }
                let reported = Self.withoutTrailingSlash(dir)
                return !(reported == base || reported.hasPrefix(base + "/"))
            }
        }
    }

    /// `directory` is the box's working directory when it has one. Reports
    /// scoped to that directory, or anywhere inside it, count toward the box,
    /// which is what happens with monorepos and worktrees.
    public func state(forBox name: String, directory: String?) -> Status? {
        lock.lock()
        defer { lock.unlock() }
        // Both sides are stripped of a trailing separator before comparing.
        // `BoxSpec.dir` comes from user-authored TOML, so a box may be written
        // as "~/w/a/" while a reporter's cwd arrives as "/w/a" — comparing raw
        // strings would silently fail to match a box against its own root
        // directory, the single most common place a report comes from.
        let base = directory.map(Self.withoutTrailingSlash)
        return reports.values
            .filter { report in
                switch report.scope {
                case .box(let boxName):
                    return boxName == name
                case .directory(let dir):
                    guard let base else { return false }
                    let reported = Self.withoutTrailingSlash(dir)
                    return reported == base || reported.hasPrefix(base + "/")
                }
            }
            .compactMap(\.state)
            .min { $0.urgency < $1.urgency }
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
