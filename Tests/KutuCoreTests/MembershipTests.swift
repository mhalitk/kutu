import Testing
import Foundation
import CoreGraphics
@testable import KutuCore

private func ref(_ id: WindowID, bundle: String = "com.example.app") -> KutuWindow {
    KutuWindow(id: id, pid: 1, bundleID: bundle, appName: "App", title: "t",
               frame: CGRect(x: 0, y: 0, width: 100, height: 100), isFullScreen: false)
}

@Test func unassignedWindowIsLoose() {
    let m = Membership()
    #expect(m.tier(of: ref(1), pinnedBundleIDs: []) == .loose)
}

@Test func looseWindowBelongsToLobby() {
    let m = Membership()
    #expect(m.boxName(for: ref(1), pinnedBundleIDs: []) == Membership.lobby)
}

@Test func assignedWindowIsBoxed() {
    var m = Membership()
    m.assign(7, to: "orchard")
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .boxed("orchard"))
    #expect(m.boxName(for: ref(7), pinnedBundleIDs: []) == "orchard")
}

@Test func perWindowPinBeatsAssignment() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(7)
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .pinned)
}

@Test func bundleLevelPinAppliesToEveryWindowOfThatApp() {
    let m = Membership()
    #expect(m.tier(of: ref(1, bundle: "com.spotify.client"),
                   pinnedBundleIDs: ["com.spotify.client"]) == .pinned)
}

@Test func unpinRestoresPreviousAssignment() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(7)
    m.unpin(7)
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .boxed("orchard"))
}

@Test func forgetRemovesAllTraceOfAWindow() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(7)
    m.forget(7)
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .loose)
}

@Test func membershipRoundTripsThroughJSON() throws {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(9)
    let data = try JSONEncoder().encode(m)
    let decoded = try JSONDecoder().decode(Membership.self, from: data)
    #expect(decoded == m)
}

@Test func pruneDropsBoxedAssignmentForDeadWindowAndKeepsLiveOne() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.assign(8, to: "orchard")
    m.prune(livingWindowIDs: [8])
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .loose)
    #expect(m.tier(of: ref(8), pinnedBundleIDs: []) == .boxed("orchard"))
}

@Test func pruneDropsPinForDeadWindowAndKeepsLiveOne() {
    var m = Membership()
    m.pin(7)
    m.pin(8)
    m.prune(livingWindowIDs: [8])
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .loose)
    #expect(m.tier(of: ref(8), pinnedBundleIDs: []) == .pinned)
}

@Test func pruneWithEmptyLivingSetClearsEverything() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(9)
    m.prune(livingWindowIDs: [])
    #expect(m.tier(of: ref(7), pinnedBundleIDs: []) == .loose)
    #expect(m.tier(of: ref(9), pinnedBundleIDs: []) == .loose)
}

@Test func pruneIsNoOpWhenEveryIDIsAlive() {
    var m = Membership()
    m.assign(7, to: "orchard")
    m.pin(9)
    let before = m
    m.prune(livingWindowIDs: [7, 9])
    #expect(m == before)
}

@Test func assignmentCountReflectsBoxedPlusPinned() {
    var m = Membership()
    #expect(m.assignmentCount == 0)
    m.assign(7, to: "orchard")
    m.pin(9)
    #expect(m.assignmentCount == 2)
}
