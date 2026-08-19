import Testing
import CoreGraphics
@testable import KutuCore

private let mainScreen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
private let secondScreen = CGRect(x: 2056, y: 0, width: 1728, height: 1117)

@Test func normalCentredFrameIsNotParked() {
    let frame = CGRect(x: 500, y: 300, width: 800, height: 600)
    #expect(!Geometry.looksParked(frame, screens: [mainScreen]))
}

@Test func frameAtTheExactParkCornerIsParked() {
    let frame = CGRect(x: 2016, y: 1328, width: 40, height: 1)
    #expect(Geometry.looksParked(frame, screens: [mainScreen]))
}

@Test func frameNearTheParkCornerOnlyOnTheXAxisIsStillParked() {
    // The clamp leaves the title bar visible, so y can land short of the
    // extreme while x sits exactly at it — either axis alone must trigger.
    let frame = CGRect(x: 2016, y: 1297, width: 40, height: 32)
    #expect(Geometry.looksParked(frame, screens: [mainScreen]))
}

@Test func topLeftFrameJustUnderTheMenuBarIsNotParked() {
    let frame = CGRect(x: 0, y: 39, width: 800, height: 600)
    #expect(!Geometry.looksParked(frame, screens: [mainScreen]))
}

@Test func frameAtTheFarEdgeOfASecondScreenIsParked() {
    let frame = CGRect(x: 3704, y: 1116, width: 40, height: 1)
    #expect(Geometry.looksParked(frame, screens: [mainScreen, secondScreen]))
}

@Test func withNoScreensNothingIsParked() {
    let frame = CGRect(x: 2016, y: 1328, width: 40, height: 1)
    #expect(!Geometry.looksParked(frame, screens: []))
}
