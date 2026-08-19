// Tests/KutuCoreTests/GeometryTests.swift
import Testing
import CoreGraphics
@testable import KutuCore

private let mainScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
private let secondScreen = CGRect(x: 579, y: -1117, width: 1728, height: 1117)
/// The single screen from the incident that motivated `looksParked`:
/// the laptop alone after the external display was disconnected.
private let laptopScreen = CGRect(x: 0, y: 0, width: 2056, height: 1329)

@Test func visibleUnionOfAFrameWhollyOnAScreenReturnsItself() {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(Geometry.visibleUnion(of: [frame], screens: [mainScreen]) == frame)
}

@Test func visibleUnionOfAFrameStraddlingAnEdgeReturnsOnlyTheOnScreenPart() {
    // Sits mostly off the right edge of a 100x100 screen.
    let frame = CGRect(x: 80, y: 0, width: 100, height: 50)
    let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
    let expected = CGRect(x: 80, y: 0, width: 20, height: 50)
    #expect(Geometry.visibleUnion(of: [frame], screens: [screen]) == expected)
}

@Test func visibleUnionOfAFrameOnNoScreenReturnsNil() {
    let frame = CGRect(x: 60000, y: 60000, width: 40, height: 40)
    #expect(Geometry.visibleUnion(of: [frame], screens: [mainScreen, secondScreen]) == nil)
}

@Test func visibleUnionOfSeveralFramesReturnsTheirUnion() {
    let a = CGRect(x: 0, y: 0, width: 10, height: 10)
    let b = CGRect(x: 50, y: 50, width: 10, height: 10)
    let expected = a.union(b)
    #expect(Geometry.visibleUnion(of: [a, b], screens: [mainScreen]) == expected)
}

@Test func visibleUnionOfEmptyInputReturnsNil() {
    #expect(Geometry.visibleUnion(of: [], screens: [mainScreen, secondScreen]) == nil)
}

@Test func reachableFrameAlreadyIntersectingIsReturnedUnchanged() {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(Geometry.reachable(frame, screens: [mainScreen]) == frame)
}

@Test func reachableFrameEntirelyOffScreenIsMovedOntoTheNearestScreenAndIntersectsIt() {
    let frame = CGRect(x: 60000, y: 60000, width: 40, height: 64)
    let result = Geometry.reachable(frame, screens: [mainScreen, secondScreen])
    let intersectsSomeScreen = !mainScreen.intersection(result).isEmpty
        || !secondScreen.intersection(result).isEmpty
    #expect(intersectsSomeScreen)
}

@Test func reachableFrameLargerThanEveryScreenIsShrunkToFit() {
    let frame = CGRect(x: 60000, y: 60000, width: 5000, height: 5000)
    let result = Geometry.reachable(frame, screens: [mainScreen, secondScreen])
    #expect(result.width <= mainScreen.width || result.width <= secondScreen.width)
    #expect(result.height <= mainScreen.height || result.height <= secondScreen.height)
    #expect(!mainScreen.intersection(result).isEmpty || !secondScreen.intersection(result).isEmpty)
}

@Test func reachableWithEmptyScreensReturnsFrameUnchangedRatherThanCrashing() {
    let frame = CGRect(x: 60000, y: 60000, width: 40, height: 64)
    #expect(Geometry.reachable(frame, screens: []) == frame)
}

@Test func normalCentredFrameIsNotParked() {
    let frame = CGRect(x: 500, y: 300, width: 800, height: 600)
    #expect(!Geometry.looksParked(frame, screens: [mainScreen]))
}

@Test func frameAtTheExactParkCornerIsParked() {
    let frame = CGRect(x: 2016, y: 1328, width: 40, height: 1)
    #expect(Geometry.looksParked(frame, screens: [laptopScreen]))
}

@Test func frameNearTheParkCornerOnlyOnTheXAxisIsStillParked() {
    // The clamp leaves the title bar visible, so y can land short of the
    // extreme while x sits exactly at it — either axis alone must trigger.
    let frame = CGRect(x: 2016, y: 1297, width: 40, height: 32)
    #expect(Geometry.looksParked(frame, screens: [laptopScreen]))
}

@Test func topLeftFrameJustUnderTheMenuBarIsNotParked() {
    let frame = CGRect(x: 0, y: 39, width: 800, height: 600)
    #expect(!Geometry.looksParked(frame, screens: [laptopScreen]))
}

@Test func frameAtTheFarEdgeOfASecondScreenIsParked() {
    let frame = CGRect(x: 3704, y: 1116, width: 40, height: 1)
    #expect(Geometry.looksParked(frame, screens: [mainScreen, secondScreen]))
}

@Test func withNoScreensNothingIsParked() {
    let frame = CGRect(x: 2016, y: 1328, width: 40, height: 1)
    #expect(!Geometry.looksParked(frame, screens: []))
}

@Test func defaultFrameForASizeSmallerThanTheScreenSitsInsideItAtTheInset() {
    let result = Geometry.defaultFrame(forSize: CGSize(width: 800, height: 600), screens: [laptopScreen])
    #expect(result.origin == CGPoint(x: 40, y: 40))
    #expect(result.size == CGSize(width: 800, height: 600))
    #expect(laptopScreen.contains(result))
}

@Test func defaultFrameForASizeLargerThanTheScreenIsShrunkToFitAndFullyInside() {
    let result = Geometry.defaultFrame(forSize: CGSize(width: 5000, height: 5000), screens: [laptopScreen])
    #expect(result.width <= laptopScreen.width)
    #expect(result.height <= laptopScreen.height)
    #expect(laptopScreen.contains(result))
}

@Test func defaultFrameWithNoScreensReturnsTheSizeAtTheOriginWithoutCrashing() {
    let size = CGSize(width: 800, height: 600)
    #expect(Geometry.defaultFrame(forSize: size, screens: []) == CGRect(origin: .zero, size: size))
}

@Test func defaultFrameIsNeverItselfLooksParked() {
    let result = Geometry.defaultFrame(forSize: CGSize(width: 800, height: 600), screens: [laptopScreen])
    #expect(!Geometry.looksParked(result, screens: [laptopScreen]))
}
