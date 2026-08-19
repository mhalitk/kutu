// Tests/KutuCoreTests/StateFileTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import KutuCore

private func tempPath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("kutu-test-\(UUID().uuidString)")
        .appendingPathComponent("state.json").path
}

private func kutuWindow(_ id: WindowID) -> KutuWindow {
    KutuWindow(id: id, pid: 1, bundleID: "b", appName: "A", title: "t",
               frame: .zero, isFullScreen: false)
}

@Test func loadingAbsentFileYieldsEmptyState() {
    let store = StateFile(path: tempPath())
    let state = store.load()
    #expect(state.parkedFrames.isEmpty)
    #expect(state.activeBox == Membership.lobby)
}

@Test func stateRoundTripsThroughDisk() throws {
    let path = tempPath()
    let store = StateFile(path: path)
    var state = PersistedState()
    state.membership.assign(42, to: "orchard")
    state.parkedFrames["42"] = CGRect(x: 10, y: 20, width: 300, height: 400)
    state.activeBox = "orchard"
    try store.save(state)

    let reloaded = StateFile(path: path).load()
    #expect(reloaded.activeBox == "orchard")
    #expect(reloaded.parkedFrames["42"] == CGRect(x: 10, y: 20, width: 300, height: 400))
    #expect(reloaded.membership == state.membership)
}

@Test func saveCreatesMissingDirectories() throws {
    let path = tempPath()
    try StateFile(path: path).save(PersistedState())
    #expect(FileManager.default.fileExists(atPath: path))
}

@Test func corruptFileDegradesToEmptyStateRatherThanCrashing() throws {
    let path = tempPath()
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: path).deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try "not json at all".write(toFile: path, atomically: true, encoding: .utf8)
    let state = StateFile(path: path).load()
    #expect(state.parkedFrames.isEmpty)
}

@Test func storeWritesThroughOnEveryMutation() throws {
    let path = tempPath()
    let store = StateStore(file: StateFile(path: path))
    store.mutate { $0.membership.assign(1, to: "alpha") }
    store.mutate { $0.activeBox = "alpha" }

    let onDisk = StateFile(path: path).load()
    #expect(onDisk.activeBox == "alpha")
    #expect(onDisk.membership == store.membership)
}

@Test func writesToDifferentFieldsCompose() throws {
    let path = tempPath()
    let store = StateStore(file: StateFile(path: path))
    // Mimics Parker and Switcher writing different fields of the same file.
    store.mutate { $0.parkedFrames["7"] = CGRect(x: 1, y: 2, width: 3, height: 4) }
    store.mutate { $0.membership.assign(9, to: "beta") }

    let onDisk = StateFile(path: path).load()
    #expect(onDisk.parkedFrames["7"] == CGRect(x: 1, y: 2, width: 3, height: 4))
    #expect(onDisk.membership.tier(of: kutuWindow(9), pinnedBundleIDs: []) == .boxed("beta"))
}

@Test func concurrentWritersDoNotClobberEachOther() throws {
    // A real interleaving test: with the save outside the lock, two writers'
    // atomic renames can land out of order and drop a mutation. Every one of
    // these 50 writes must survive to disk.
    let path = tempPath()
    let store = StateStore(file: StateFile(path: path))

    DispatchQueue.concurrentPerform(iterations: 50) { index in
        if index.isMultiple(of: 2) {
            store.mutate { $0.parkedFrames["\(index)"] = CGRect(x: CGFloat(index), y: 0, width: 1, height: 1) }
        } else {
            store.mutate { $0.membership.assign(WindowID(index), to: "box-\(index)") }
        }
    }

    let onDisk = StateFile(path: path).load()
    #expect(onDisk.parkedFrames.count == 25)
    for index in stride(from: 1, to: 50, by: 2) {
        #expect(onDisk.membership.tier(of: kutuWindow(WindowID(index)),
                                       pinnedBundleIDs: []) == .boxed("box-\(index)"))
    }
}

@Test func storeStartsFromWhateverIsOnDisk() throws {
    let path = tempPath()
    var seed = PersistedState()
    seed.activeBox = "seeded"
    try StateFile(path: path).save(seed)
    #expect(StateStore(file: StateFile(path: path)).activeBox == "seeded")
}

@Test func lastFocusedRoundTripsThroughDisk() throws {
    let path = tempPath()
    var state = PersistedState()
    state.lastFocused["orchard"] = 42
    try StateFile(path: path).save(state)

    let reloaded = StateFile(path: path).load()
    #expect(reloaded.lastFocused == ["orchard": 42])
}

// A live state.json predates `lastFocused`. Decoding it must still succeed —
// with the field defaulting to empty — rather than failing and losing the
// user's boxes to `StateFile.load()`'s corrupt-file fallback.
@Test func stateWrittenBeforeLastFocusedExistedStillDecodes() throws {
    let json = """
    {
        "membership": {"boxed": {"42": "orchard"}, "pinnedWindows": []},
        "parkedFrames": {},
        "activeBox": "orchard"
    }
    """
    let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
    #expect(decoded.activeBox == "orchard")
    #expect(decoded.lastFocused.isEmpty)
    #expect(decoded.membership.tier(of: kutuWindow(42), pinnedBundleIDs: []) == .boxed("orchard"))
}
