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
  kutu ls                           list boxes
  kutu status <box> <state>         report working | waiting | idle for a box
  kutu status <box> clear           retract a previously reported status
  kutu panic                        unpark every hidden window

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
