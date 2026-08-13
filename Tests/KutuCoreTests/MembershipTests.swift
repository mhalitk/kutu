import Testing
import Foundation
import CoreGraphics
@testable import KutuCore

private func ref(_ id: WindowID, bundle: String = "com.example.app") -> WindowRef {
    WindowRef(id: id, pid: 1, bundleID: bundle, appName: "App", title: "t",
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
