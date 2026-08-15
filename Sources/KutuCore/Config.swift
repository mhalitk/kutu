import Foundation
import TOMLKit

public struct BoxSpec: Sendable, Equatable, Codable {
    public let name: String
    public let dir: String
    public init(name: String, dir: String) {
        self.name = name
        self.dir = dir
    }
}

public struct KutuConfig: Sendable, Equatable {
    /// Governs what happens when the user cmd+tabs to an application whose
    /// windows are all parked in another box.
    public enum CmdTabBehaviour: String, Sendable, Equatable {
        case notify   // default: never switch, just say where the app lives
        case `switch` // legacy: jump to the box that owns the window
    }

    public let hotkey: String
    public let pinnedBundleIDs: [String]
    public let boxes: [BoxSpec]
    public let cmdTab: CmdTabBehaviour

    public init(hotkey: String = "alt+space", pinnedBundleIDs: [String] = [], boxes: [BoxSpec] = [],
                cmdTab: CmdTabBehaviour = .notify) {
        self.hotkey = hotkey
        self.pinnedBundleIDs = pinnedBundleIDs
        self.boxes = boxes
        self.cmdTab = cmdTab
    }

    public static func parse(_ toml: String) throws -> KutuConfig {
        let table = try TOMLTable(string: toml)
        var boxes: [BoxSpec] = []
        if let array = table["box"]?.array {
            for index in 0..<array.count {
                guard let entry = array[index].table,
                      let name = entry["name"]?.string,
                      let dir = entry["dir"]?.string else { continue }
                boxes.append(BoxSpec(name: name, dir: (dir as NSString).expandingTildeInPath))
            }
        }
        var pinned: [String] = []
        if let array = table["pinned"]?.array {
            for index in 0..<array.count {
                if let value = array[index].string { pinned.append(value) }
            }
        }
        let cmdTab = table["cmd_tab"]?.string.flatMap(KutuConfig.CmdTabBehaviour.init(rawValue:)) ?? .notify
        return KutuConfig(
            hotkey: table["hotkey"]?.string ?? "alt+space",
            pinnedBundleIDs: pinned,
            boxes: boxes,
            cmdTab: cmdTab
        )
    }

    /// Reads `~/.config/kutu/boxes.toml`, returning defaults when absent.
    public static func load(from path: String) throws -> KutuConfig {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return KutuConfig() }
        return try parse(text)
    }
}

public struct AppSpec: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case iterm, chrome, vscode, app, firefox
    }
    public let kind: Kind
    public let cmd: String?
    public let profile: String?
    public let urls: [String]
    public let bundleID: String?

    public init(kind: Kind, cmd: String? = nil, profile: String? = nil, urls: [String] = [], bundleID: String? = nil) {
        self.kind = kind
        self.cmd = cmd
        self.profile = profile
        self.urls = urls
        self.bundleID = bundleID
    }
}

public struct BoxManifest: Sendable, Equatable, Codable {
    public let name: String
    public let apps: [AppSpec]

    public init(name: String, apps: [AppSpec]) {
        self.name = name
        self.apps = apps
    }

    public static func parse(_ toml: String) throws -> BoxManifest {
        let table = try TOMLTable(string: toml)
        var apps: [AppSpec] = []
        if let array = table["app"]?.array {
            for index in 0..<array.count {
                guard let entry = array[index].table,
                      let rawKind = entry["kind"]?.string,
                      let kind = AppSpec.Kind(rawValue: rawKind) else { continue }
                var urls: [String] = []
                if let urlArray = entry["urls"]?.array {
                    for i in 0..<urlArray.count {
                        if let value = urlArray[i].string { urls.append(value) }
                    }
                }
                apps.append(AppSpec(
                    kind: kind,
                    cmd: entry["cmd"]?.string,
                    profile: entry["profile"]?.string,
                    urls: urls,
                    bundleID: entry["bundle_id"]?.string
                ))
            }
        }
        return BoxManifest(name: table["name"]?.string ?? "", apps: apps)
    }
}
