import Testing
import Foundation
import CoreGraphics
@testable import KutuCore

private func ref(_ id: WindowID, bundle: String = "com.example.app") -> WindowRef {
    WindowRef(id: id, pid: 1, bundleID: bundle, appName: "App", title: "t",
              frame: CGRect(x: 0, y: 0, width: 100, height: 100), isFullScreen: false)
}

@Test func targetBoxWindowsAreUnparkedAndOthersParked() {
    var m = Membership()
    m.assign(1, to: "orchard")
    m.assign(2, to: "haber")
    let plan = SwitchPlan.compute(all: [ref(1), ref(2)], membership: m,
                                  pinnedBundleIDs: [], target: "orchard")
    #expect(plan.toUnpark == [1])
    #expect(plan.toPark == [2])
}

@Test func pinnedWindowsAreNeverParked() {
    var m = Membership()
    m.assign(1, to: "orchard")
    m.pin(2)
    let plan = SwitchPlan.compute(all: [ref(1), ref(2)], membership: m,
                                  pinnedBundleIDs: [], target: "orchard")
    #expect(plan.toUnpark.sorted() == [1, 2])
    #expect(plan.toPark.isEmpty)
}

@Test func looseWindowsAreParkedOutsideLobby() {
    var m = Membership()
    m.assign(1, to: "orchard")
    let plan = SwitchPlan.compute(all: [ref(1), ref(2)], membership: m,
                                  pinnedBundleIDs: [], target: "orchard")
    #expect(plan.toPark == [2])
}

@Test func looseWindowsAreVisibleInLobby() {
    var m = Membership()
    m.assign(1, to: "orchard")
    let plan = SwitchPlan.compute(all: [ref(1), ref(2)], membership: m,
                                  pinnedBundleIDs: [], target: Membership.lobby)
    #expect(plan.toUnpark == [2])
    #expect(plan.toPark == [1])
}

@Test func fullScreenWindowsAreNeverParked() {
    var m = Membership()
    m.assign(1, to: "haber")
    let full = WindowRef(id: 1, pid: 1, bundleID: "b", appName: "A", title: "t",
                         frame: .zero, isFullScreen: true)
    let plan = SwitchPlan.compute(all: [full], membership: m,
                                  pinnedBundleIDs: [], target: "orchard")
    #expect(plan.toPark.isEmpty)
}

@Test func noWindowIsEverBothParkedAndUnparked() {
    var m = Membership()
    m.assign(1, to: "orchard")
    m.assign(2, to: "haber")
    m.pin(3)
    let plan = SwitchPlan.compute(all: [ref(1), ref(2), ref(3)], membership: m,
                                  pinnedBundleIDs: [], target: "orchard")
    #expect(Set(plan.toPark).isDisjoint(with: Set(plan.toUnpark)))
    #expect(plan.toPark.count + plan.toUnpark.count == 3)
}

@Test func bundlePinnedAppSurvivesEverySwitch() {
    var m = Membership()
    m.assign(1, to: "orchard")
    let plan = SwitchPlan.compute(all: [ref(1), ref(2, bundle: "com.spotify.client")],
                                  membership: m,
                                  pinnedBundleIDs: ["com.spotify.client"],
                                  target: "orchard")
    #expect(plan.toUnpark.sorted() == [1, 2])
}
