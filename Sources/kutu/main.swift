import Foundation
import KutuCore

let socketPath = StatusSocket.defaultPath

enum StatusSocket {
    static var defaultPath: String { KutuPaths.socket }
}

func send(_ message: ControlMessage) -> Bool {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    // Size is read before taking the pointer: computing it inside the closure
    // is an overlapping access to `address.sun_path` and violates exclusivity.
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path) - 1
    _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        socketPath.withCString { source in
            strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source, maxPathLength)
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) }
    }
    guard connected == 0, let payload = try? JSONEncoder().encode(message) else { return false }
    return payload.withUnsafeBytes { write(descriptor, $0.baseAddress, payload.count) } > 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
let usage = """
usage:
  kutu go <box>                     switch to a box
  kutu open <box>                   switch to a box, launching its kutu.toml apps
  kutu move <box>                   move the frontmost window to a box
  kutu ls                           list boxes
  kutu status <box> <state>         report working | waiting | idle for a box
  kutu status <box> clear           retract a previously reported status
  kutu panic                        unpark every hidden window
  kutu register                     add this directory's kutu.toml box to boxes.toml
  kutu reload                       tell the running kutu to re-read boxes.toml

any tool can report status directly:
  echo '{"kutu":"status","arg":"myBox","state":"working"}' | nc -U \(socketPath)
"""

switch arguments.first {
case "go", "open":
    guard arguments.count == 2 else {
        print(usage)
        exit(1)
    }
    exit(send(ControlMessage(kutu: arguments[0] == "open" ? "open" : "switch",
                             arg: arguments[1])) ? 0 : 1)

case "move":
    guard arguments.count == 2 else {
        print(usage)
        exit(1)
    }
    exit(send(ControlMessage(kutu: "move", arg: arguments[1])) ? 0 : 1)

case "status":
    guard arguments.count == 3 else {
        print(usage)
        exit(1)
    }
    let box = arguments[1]
    let raw = arguments[2]
    guard raw == "clear" || Status(rawValue: raw) != nil else {
        print("state must be one of: working, waiting, idle, clear")
        exit(1)
    }
    exit(send(ControlMessage(kutu: "status",
                             arg: box,
                             state: raw == "clear" ? nil : raw,
                             key: "cli:\(box)")) ? 0 : 1)

case "panic":
    exit(send(ControlMessage(kutu: "panic")) ? 0 : 1)

case "reload":
    exit(send(ControlMessage(kutu: "reload")) ? 0 : 1)

case "register":
    guard arguments.count == 1 else {
        print(usage)
        exit(1)
    }
    let cwd = FileManager.default.currentDirectoryPath
    let manifestPath = (cwd as NSString).appendingPathComponent("kutu.toml")
    guard let manifestText = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
        print("no kutu.toml at \(manifestPath) — see the manifest format `kutu open` expects (README).")
        exit(1)
    }
    let manifest: BoxManifest
    do {
        manifest = try BoxManifest.parse(manifestText)
    } catch {
        print("could not parse \(manifestPath): \(error)")
        exit(1)
    }
    guard !manifest.name.isEmpty else {
        print("\(manifestPath) has no `name` — a box needs one to be registered.")
        exit(1)
    }
    let home = NSHomeDirectory()
    let displayDir = BoxRegistration.displayPath(cwd, home: home)
    let config = (try? KutuConfig.load(from: KutuPaths.config)) ?? KutuConfig()

    switch BoxRegistration.plan(existing: config, name: manifest.name, dir: displayDir) {
    case .alreadyRegistered:
        print("\(manifest.name) is already registered.")
        exit(0)

    case .conflict(let existingDir):
        print("""
        \(manifest.name) is already registered to a different directory:
          existing:  \(existingDir)
          this dir:  \(displayDir)
        Edit \(KutuPaths.config) directly if this is intentional.
        """)
        exit(1)

    case .append(let block):
        let configDir = (KutuPaths.config as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        var text = (try? String(contentsOfFile: KutuPaths.config, encoding: .utf8)) ?? ""
        if text.isEmpty {
            text = String(block.dropFirst())   // no leading blank line in a brand-new file
        } else {
            if !text.hasSuffix("\n") { text += "\n" }
            text += block
        }
        do {
            try text.write(toFile: KutuPaths.config, atomically: true, encoding: .utf8)
        } catch {
            print("could not write \(KutuPaths.config): \(error)")
            exit(1)
        }

        print("registered \(manifest.name) -> \(displayDir)")
        if manifest.apps.isEmpty {
            print("  (no [[app]] entries — kutu open will just switch to the box)")
        }
        for app in manifest.apps {
            if let command = LaunchCommand.build(for: app, in: cwd) {
                // The CLI links only KutuCore, which has no LaunchServices
                // access, so an .appBundle target is printed by its bundle
                // id rather than resolved to a path.
                let executable: String
                switch command.target {
                case .path(let path): executable = path
                case .appBundle(let bundleID): executable = bundleID
                }
                print("  " + ([executable] + command.arguments).joined(separator: " "))
            } else {
                print("  [\(app.kind.rawValue)] produces no launch command — check its fields in kutu.toml")
            }
        }

        if send(ControlMessage(kutu: "reload")) {
            print("reloaded the running kutu.")
        } else {
            print("kutu does not appear to be running — restart it, or use \"Reload config\" in the menu bar, to pick this up.")
        }
        exit(0)
    }

case "ls":
    let config = (try? KutuConfig.load(from: KutuPaths.config)) ?? KutuConfig()
    for box in config.boxes { print("\(box.name)\t\(box.dir)") }
    print(Membership.lobby)

default:
    // Unknown subcommand is an error, not a help request — a script checking
    // exit codes must not read a typo as success.
    print(usage)
    exit(1)
}
