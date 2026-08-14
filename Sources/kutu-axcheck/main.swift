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

Check.emit("=== WindowRegistry ===")

let registry = WindowRegistry()
registry.start()
Thread.sleep(forTimeInterval: 0.5)

Check.run("initial sweep finds the same windows as a direct scan") {
    let direct = Set(AXBridge.allStandardWindows().map(\.ref.id))
    let seen = Set(registry.windows.map(\.id))
    return (seen == direct, "registry \(seen.count) vs direct \(direct.count)")
}

var added: [WindowID] = []
var removed: [WindowID] = []
registry.onWindowAdded = { added.append($0.id) }
registry.onWindowRemoved = { removed.append($0) }

let newFile = scratch.appendingPathComponent("registry.txt")
try? "kutu".write(to: newFile, atomically: true, encoding: .utf8)
let openNew = Process()
openNew.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openNew.arguments = ["-a", "TextEdit", newFile.path]
try? openNew.run()
openNew.waitUntilExit()

// AX notifications arrive on the run loop, so pump it rather than sleeping.
let addDeadline = Date().addingTimeInterval(5)
while added.isEmpty && Date() < addDeadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

Check.run("observes a newly created window") {
    (!added.isEmpty, "added \(added.count)")
}

Check.run("resolves an element for the new window") {
    guard let id = added.first else { return (false, "nothing added") }
    return (registry.element(for: id) != nil, "id \(id)")
}

closeAll(AXBridge.allStandardWindows().filter { $0.ref.bundleID == "com.apple.TextEdit" })
let removeDeadline = Date().addingTimeInterval(5)
while removed.isEmpty && Date() < removeDeadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

Check.run("observes a closed window") {
    (!removed.isEmpty, "removed \(removed.count)")
}

registry.stop()

Check.emit("=== Switcher ===")

let switchFiles = (0..<2).map { scratch.appendingPathComponent("switch-\($0).txt") }
for file in switchFiles { try? "kutu".write(to: file, atomically: true, encoding: .utf8) }
let openSwitch = Process()
openSwitch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openSwitch.arguments = ["-a", "TextEdit"] + switchFiles.map(\.path)
try? openSwitch.run()
openSwitch.waitUntilExit()
Thread.sleep(forTimeInterval: 2.0)

let switchRegistry = WindowRegistry()
switchRegistry.start()
switchRegistry.refresh()

let switchStatePath = scratch.appendingPathComponent("switch-state.json").path
let switchStore = StateStore(file: StateFile(path: switchStatePath))
let switchParker = Parker(resolver: switchRegistry, store: switchStore)
let switcher = Switcher(registry: switchRegistry, parker: switchParker,
                        store: switchStore, config: KutuConfig())

let editorWindows = switchRegistry.windows.filter { $0.bundleID == "com.apple.TextEdit" }

Check.run("two windows available to box up") {
    (editorWindows.count >= 2, "found \(editorWindows.count)")
}

switcher.assign(editorWindows[0].id, to: "alpha")
switcher.assign(editorWindows[1].id, to: "beta")

Check.run("switching to alpha hides beta's window") {
    switcher.switchTo("alpha")
    Thread.sleep(forTimeInterval: 0.4)
    return (switchParker.isParked(editorWindows[1].id) && !switchParker.isParked(editorWindows[0].id),
            "alpha parked=\(switchParker.isParked(editorWindows[0].id)) beta parked=\(switchParker.isParked(editorWindows[1].id))")
}

Check.run("switching to beta reverses it") {
    switcher.switchTo("beta")
    Thread.sleep(forTimeInterval: 0.4)
    return (switchParker.isParked(editorWindows[0].id) && !switchParker.isParked(editorWindows[1].id), "")
}

Check.run("active box survives a restart") {
    let reloaded = StateFile(path: switchStatePath).load()
    return (reloaded.activeBox == "beta", "got \(reloaded.activeBox)")
}

Check.run("lobby shows unclassified windows") {
    switcher.switchTo(Membership.lobby)
    Thread.sleep(forTimeInterval: 0.4)
    return (switchParker.isParked(editorWindows[0].id) && switchParker.isParked(editorWindows[1].id),
            "boxed windows must hide in lobby")
}

Check.emit("=== Assigner ===")

let assigner = Assigner(switcher: switcher)

Check.run("a claimed window joins the claiming box, not the active one") {
    guard let window = editorWindows.first else { return (false, "no window") }
    switcher.switchTo("alpha")
    assigner.claimNextWindows(for: "gamma", seconds: 10)
    assigner.windowAppeared(window)
    let box = switcher.membership.boxName(for: window, pinnedBundleIDs: [])
    return (box == "gamma", "got \(box)")
}

Check.run("an expired claim falls back to the active box") {
    guard let window = editorWindows.first else { return (false, "no window") }
    assigner.claimNextWindows(for: "gamma", seconds: 0)
    switcher.switchTo("alpha")
    assigner.windowAppeared(window)
    let box = switcher.membership.boxName(for: window, pinnedBundleIDs: [])
    return (box == "alpha", "got \(box)")
}

Check.run("a window appearing while lobby is active stays loose") {
    guard let window = editorWindows.last else { return (false, "no window") }
    // Make the window visible BEFORE forgetting it. `forget` drops the saved
    // frame, and dropping it while the window is still parked strands it
    // off-screen with no record of where it belongs — the very hazard this
    // task fixed. Production only calls forget on window-close, where position
    // no longer matters; the harness must not exercise it outside that
    // contract.
    switcher.switchTo("beta")
    switcher.forget(window.id)
    switcher.switchTo(Membership.lobby)
    assigner.windowAppeared(window)
    let box = switcher.membership.boxName(for: window, pinnedBundleIDs: [])
    // Assert position too, not just membership: asserting the box name alone
    // would let a stranded window pass.
    return (box == Membership.lobby && !switchParker.isParked(window.id),
            "box \(box), parked \(switchParker.isParked(window.id))")
}

switcher.switchTo("alpha")
switchParker.unparkAll()
switchRegistry.stop()
closeAll(AXBridge.allStandardWindows().filter { $0.ref.bundleID == "com.apple.TextEdit" })

Check.emit("=== Recovery ===")

let recoveryFile = scratch.appendingPathComponent("recovery.txt")
try? "kutu".write(to: recoveryFile, atomically: true, encoding: .utf8)
let openRecovery = Process()
openRecovery.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openRecovery.arguments = ["-a", "TextEdit", recoveryFile.path]
try? openRecovery.run()
openRecovery.waitUntilExit()
Thread.sleep(forTimeInterval: 2.0)

let recoveryRegistry = WindowRegistry()
recoveryRegistry.start()
recoveryRegistry.refresh()
let recoveryPath = scratch.appendingPathComponent("recovery.json").path
let recoveryParker = Parker(resolver: recoveryRegistry, store: StateStore(file: StateFile(path: recoveryPath)))

guard let victim = recoveryRegistry.windows.first(where: { $0.bundleID == "com.apple.TextEdit" }) else {
    Check.run("recovery window exists") { (false, "no TextEdit window") }
    Check.finish()
}
let victimFrame = victim.frame

Check.run("a window parked by a dead run is rescued on relaunch") {
    _ = recoveryParker.park(victim)
    Thread.sleep(forTimeInterval: 0.3)

    // Simulate relaunch: brand new Parker reading the same state file, then
    // reconcile against a membership that no longer mentions the window.
    let revived = Parker(resolver: recoveryRegistry, store: StateStore(file: StateFile(path: recoveryPath)))
    recoveryRegistry.refresh()
    revived.reconcile(activeBox: Membership.lobby,
                      membership: Membership(),
                      pinnedBundleIDs: [],
                      windows: recoveryRegistry.windows)
    Thread.sleep(forTimeInterval: 0.3)

    recoveryRegistry.refresh()
    guard let now = recoveryRegistry.windows.first(where: { $0.id == victim.id }) else {
        return (false, "window disappeared")
    }
    let restored = abs(now.frame.minX - victimFrame.minX) < 2 && abs(now.frame.minY - victimFrame.minY) < 2
    return (restored, "want \(victimFrame.origin) got \(now.frame.origin)")
}

Check.run("a frame whose window is alive but missing from the sweep is kept") {
    // The branch the CGWindowList cross-check exists for. Simulates an app
    // still launching, or too busy to answer Accessibility within the
    // messaging timeout: absent from the sweep while its window plainly still
    // exists. Pruning here would strand it permanently, so passing an empty
    // sweep must NOT discard the frame.
    recoveryRegistry.refresh()
    guard let live = recoveryRegistry.windows.first(where: { $0.id == victim.id }) else {
        return (false, "victim window disappeared")
    }
    // A FRESH store, deliberately. A StateStore caches its state at init and
    // only updates it through its own mutate calls, so `recoveryParker`'s copy
    // is stale the moment the previous check unparked through a different
    // instance. Parking through a stale cache makes `park` see a phantom entry,
    // silently no-op, and leave this check asserting on state nothing wrote.
    let parkerForCheck = Parker(resolver: recoveryRegistry,
                                store: StateStore(file: StateFile(path: recoveryPath)))
    // Assert the park actually happened: a silent no-op here would rob the
    // check of all discriminating power, which is exactly what it exists to
    // provide.
    guard parkerForCheck.park(live) else { return (false, "could not park the victim window") }
    Thread.sleep(forTimeInterval: 0.3)

    let blind = Parker(resolver: recoveryRegistry,
                       store: StateStore(file: StateFile(path: recoveryPath)))
    blind.reconcile(activeBox: Membership.lobby,
                    membership: Membership(),
                    pinnedBundleIDs: [],
                    windows: [])
    let kept = StateFile(path: recoveryPath).load().parkedFrames[String(victim.id)] != nil

    // Put the window back for whatever runs next.
    recoveryRegistry.refresh()
    Parker(resolver: recoveryRegistry, store: StateStore(file: StateFile(path: recoveryPath)))
        .reconcile(activeBox: Membership.lobby, membership: Membership(),
                   pinnedBundleIDs: [], windows: recoveryRegistry.windows)
    Thread.sleep(forTimeInterval: 0.3)
    return (kept, kept ? "" : "frame pruned while the window was still alive")
}

Check.run("a frame for a window the server no longer knows is pruned") {
    // The complementary half: absence from BOTH sources really does mean gone.
    let ghost: WindowID = 4_294_900_000
    let store = StateStore(file: StateFile(path: recoveryPath))
    store.mutate { $0.parkedFrames[String(ghost)] = CGRect(x: 10, y: 10, width: 100, height: 100) }
    recoveryRegistry.refresh()
    Parker(resolver: recoveryRegistry, store: store)
        .reconcile(activeBox: Membership.lobby, membership: Membership(),
                   pinnedBundleIDs: [], windows: recoveryRegistry.windows)
    let gone = StateFile(path: recoveryPath).load().parkedFrames[String(ghost)] == nil
    return (gone, gone ? "" : "stale frame for a dead window survived")
}

// Also a fresh store, for the same staleness reason.
recoveryRegistry.refresh()
Parker(resolver: recoveryRegistry, store: StateStore(file: StateFile(path: recoveryPath)))
    .unparkAll()
recoveryRegistry.stop()
closeAll(AXBridge.allStandardWindows().filter { $0.ref.bundleID == "com.apple.TextEdit" })

Check.finish()

/// `kAXCloseAction` does not exist in AXActionConstants.h, so closing a
/// window through Accessibility means locating its close button — but
/// closes it the way a user does, a real click, not an
/// `AXUIElementPerformAction` press.
///
/// Measured directly (see the WindowRegistry flaky-check investigation):
/// `AXUIElementPerformAction(closeButton, kAXPressAction)` does trigger the
/// close — the AX sweep drops the window immediately — but the window server
/// does not agree. `CGWindowListCopyWindowInfo` kept listing an AX-pressed
/// "closed" window for over 13 minutes with its owning app idle, only
/// clearing once that app's window list changed again for an unrelated
/// reason. A real click (or a real key event) on the identical button
/// settles the window server's view in well under a second, every time.
/// `WindowRegistry.refresh()` deliberately gates removal on the window
/// server agreeing — that is the fix for a Critical stranding bug, not
/// something to weaken — so this harness has to close windows the same way
/// a person would, or that gate can never be satisfied.
func closeAll(_ windows: [ManagedWindow]) {
    for window in windows {
        AXBridge.raise(window.element) // avoid clicking through an occluding window
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString,
                                            &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { continue }
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue((button as! AXUIElement), kAXPositionAttribute as CFString,
                                            &posValue) == .success,
              AXUIElementCopyAttributeValue((button as! AXUIElement), kAXSizeAttribute as CFString,
                                            &sizeValue) == .success else { continue }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue((posValue as! AXValue), .cgPoint, &origin)
        AXValueGetValue((sizeValue as! AXValue), .cgSize, &extent)
        let point = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)

        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
               mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
               mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
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
