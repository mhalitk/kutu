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

@Test func concurrentWritersDoNotClobberEachOther() throws {
    let path = tempPath()
    let store = StateStore(file: StateFile(path: path))
    // Mimics Parker and Switcher writing different fields of the same file.
    store.mutate { $0.parkedFrames["7"] = CGRect(x: 1, y: 2, width: 3, height: 4) }
    store.mutate { $0.membership.assign(9, to: "beta") }

    let onDisk = StateFile(path: path).load()
    #expect(onDisk.parkedFrames["7"] == CGRect(x: 1, y: 2, width: 3, height: 4))
    #expect(onDisk.membership.tier(of: WindowRef(id: 9, pid: 1, bundleID: "b", appName: "A",
                                                 title: "t", frame: .zero, isFullScreen: false),
                                   pinnedBundleIDs: []) == .boxed("beta"))
}

@Test func storeStartsFromWhateverIsOnDisk() throws {
    let path = tempPath()
    var seed = PersistedState()
    seed.activeBox = "seeded"
    try StateFile(path: path).save(seed)
    #expect(StateStore(file: StateFile(path: path)).activeBox == "seeded")
}
