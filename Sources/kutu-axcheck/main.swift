import AppKit
import KutuCore
import KutuMac

enum Check {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0
    nonisolated(unsafe) static var log = ""

    static let path = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".local/state/kutu/axcheck.log")

    static func emit(_ line: String) {
        log += line + "\n"
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? log.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func run(_ name: String, _ body: () -> (Bool, String)) {
        let (ok, detail) = body()
        if ok { passes += 1 } else { failures += 1 }
        emit("  \(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }

    static func finish() -> Never {
        emit("AXCHECK: \(failures == 0 ? "PASS" : "FAIL") \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

guard AXBridge.isTrusted else {
    Check.emit("AXCHECK: FAIL not trusted — grant Accessibility to KutuAXCheck")
    exit(2)
}

Check.emit("=== AXBridge ===")

Check.run("enumerates at least one standard window") {
    let windows = AXBridge.allStandardWindows()
    return (!windows.isEmpty, "found \(windows.count)")
}

Check.run("every window resolves a server-verified id") {
    let windows = AXBridge.allStandardWindows()
    let serverIDs = Set(
        ((CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                     kCGNullWindowID) as? [[String: Any]]) ?? [])
            .compactMap { $0["kCGWindowNumber"] as? UInt32 })
    let bad = windows.filter { !serverIDs.contains($0.ref.id) }
    return (bad.isEmpty, "\(bad.count) unverified of \(windows.count)")
}

Check.run("reads a position for every window") {
    let windows = AXBridge.allStandardWindows()
    let bad = windows.filter { AXBridge.position($0.element) == nil }
    return (bad.isEmpty, "\(bad.count) unreadable")
}

Check.finish()
