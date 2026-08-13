import AppKit
import ApplicationServices
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

Check.emit("=== Parker ===")

// Two real windows to abuse, created deterministically rather than by
// borrowing whatever the user happens to have open.
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("kutu-axcheck")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
let files = (0..<2).map { scratch.appendingPathComponent("park-\($0).txt") }
for file in files { try? "kutu".write(to: file, atomically: true, encoding: .utf8) }

let opener = Process()
opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
opener.arguments = ["-a", "TextEdit"] + files.map(\.path)
try? opener.run()
opener.waitUntilExit()
Thread.sleep(forTimeInterval: 2.0)

func textEditWindows() -> [ManagedWindow] {
    AXBridge.allStandardWindows().filter { $0.ref.bundleID == "com.apple.TextEdit" }
}

Check.run("stage manager is off") {
    (!StageManagerGuard.isEnabled, StageManagerGuard.isEnabled ? "disable it in Desktop & Dock" : "")
}

Check.run("opened two TextEdit windows") {
    (textEditWindows().count >= 2, "found \(textEditWindows().count)")
}

let resolver = SnapshotResolver(windows: textEditWindows())
let parkerStore = StateStore(file: StateFile(path: scratch.appendingPathComponent("state.json").path))
let parker = Parker(resolver: resolver, store: parkerStore)
let victims = textEditWindows()
let originalFrames = Dictionary(uniqueKeysWithValues: victims.map { ($0.ref.id, $0.ref.frame) })

Check.run("parks every window off-screen") {
    for window in victims { _ = parker.park(window.ref) }
    Thread.sleep(forTimeInterval: 0.3)
    let visible = NSScreen.screens.first?.frame ?? .zero
    let stillVisible = textEditWindows().filter { $0.ref.frame.minX < visible.maxX - 100 }
    return (stillVisible.isEmpty, "\(stillVisible.count) still on screen")
}

Check.run("restores every frame exactly") {
    for window in victims { _ = parker.unpark(window.ref.id) }
    Thread.sleep(forTimeInterval: 0.3)
    var wrong: [String] = []
    for window in textEditWindows() {
        guard let want = originalFrames[window.ref.id] else { continue }
        if abs(window.ref.frame.minX - want.minX) > 1 || abs(window.ref.frame.minY - want.minY) > 1 {
            wrong.append("\(window.ref.id) want \(want.origin) got \(window.ref.frame.origin)")
        }
    }
    return (wrong.isEmpty, wrong.joined(separator: "; "))
}

Check.run("unparkAll rescues windows after a simulated crash") {
    for window in victims { _ = parker.park(window.ref) }
    Thread.sleep(forTimeInterval: 0.3)
    // A fresh Parker with no memory, exactly like a relaunch after a crash.
    // Bind the resolver to a local first: an inline temporary would be released
    // before use, and every unpark would silently no-op.
    let revivedResolver = SnapshotResolver(windows: textEditWindows())
    let revived = Parker(resolver: revivedResolver,
                         store: StateStore(file: StateFile(path: scratch.appendingPathComponent("state.json").path)))
    revived.unparkAll()
    Thread.sleep(forTimeInterval: 0.3)
    let visible = NSScreen.screens.first?.frame ?? .zero
    let stranded = textEditWindows().filter { $0.ref.frame.minX > visible.maxX - 100 }
    return (stranded.isEmpty, "\(stranded.count) stranded")
}

closeAll(textEditWindows())

Check.finish()

/// `kAXCloseAction` does not exist in AXActionConstants.h. Closing a window
/// through Accessibility means pressing its close button, per Apple's pattern.
func closeAll(_ windows: [ManagedWindow]) {
    for window in windows {
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString,
                                         &button) == .success,
           let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
            AXUIElementPerformAction((button as! AXUIElement), kAXPressAction as CFString)
        }
    }
}

/// Resolves elements from a fixed snapshot — enough for the harness, which
/// knows exactly which windows it created.
final class SnapshotResolver: WindowResolving {
    private let map: [WindowID: AXUIElement]
    init(windows: [ManagedWindow]) {
        map = Dictionary(uniqueKeysWithValues: windows.map { ($0.ref.id, $0.element) })
    }
    func element(for id: WindowID) -> AXUIElement? { map[id] }
}
