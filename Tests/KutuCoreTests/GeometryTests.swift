// Tests/KutuCoreTests/GeometryTests.swift
import Testing
import CoreGraphics
@testable import KutuCore

private let mainScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
private let secondScreen = CGRect(x: 579, y: -1117, width: 1728, height: 1117)
/// The single screen from the incident that motivated `looksParked`:
/// the laptop alone after the external display was disconnected.
private let laptopScreen = CGRect(x: 0, y: 0, width: 2056, height: 1329)

@Test func visibleFragmentsOfAFrameWhollyOnAScreenIsItself() {
    let frame = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(Geometry.visibleFragments(of: [frame], screens: [mainScreen]) == [frame])
}

@Test func visibleFragmentsOfAFrameStraddlingAnEdgeIsOnlyTheOnScreenPart() {
    // Sits mostly off the right edge of a 100x100 screen.
    let frame = CGRect(x: 80, y: 0, width: 100, height: 50)
    let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
    let expected = CGRect(x: 80, y: 0, width: 20, height: 50)
    #expect(Geometry.visibleFragments(of: [frame], screens: [screen]) == [expected])
}

@Test func visibleFragmentsOfAFrameOnNoScreenIsEmpty() {
    let frame = CGRect(x: 60000, y: 60000, width: 40, height: 40)
    #expect(Geometry.visibleFragments(of: [frame], screens: [mainScreen, secondScreen]).isEmpty)
}

@Test func visibleFragmentsMergesOverlappingFrames() {
    let a = CGRect(x: 0, y: 0, width: 20, height: 20)
    let b = CGRect(x: 10, y: 10, width: 20, height: 20)
    #expect(Geometry.visibleFragments(of: [a, b], screens: [mainScreen]) == [a.union(b)])
}

@Test func visibleFragmentsKeepsDisjointFramesApart() {
    // Two slivers at the same edge but different heights: one lid over both
    // would cover the desktop between them.
    let top = CGRect(x: 2520, y: 25, width: 40, height: 32)
    let bottom = CGRect(x: 2520, y: 1400, width: 40, height: 40)
    let result = Geometry.visibleFragments(of: [top, bottom], screens: [mainScreen])
    #expect(result.count == 2)
    #expect(result.contains(top) && result.contains(bottom))
}

@Test func visibleFragmentsMergesTransitively() {
    // c bridges a and b, which do not touch each other.
    let a = CGRect(x: 0, y: 0, width: 10, height: 10)
    let b = CGRect(x: 30, y: 0, width: 10, height: 10)
    let c = CGRect(x: 5, y: 0, width: 30, height: 10)
    #expect(Geometry.visibleFragments(of: [a, b, c], screens: [mainScreen])
            == [CGRect(x: 0, y: 0, width: 40, height: 10)])
}

@Test func visibleFragmentsOfEmptyInputIsEmpty() {
    #expect(Geometry.visibleFragments(of: [], screens: [mainScreen, secondScreen]).isEmpty)
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

/// An external main display with the laptop to its left, in Accessibility
/// space: the arrangement where edge-based detection flagged every window.
private let externalMain = CGRect(x: 0, y: 0, width: 2560, height: 1440)
private let laptopLeft = CGRect(x: -1728, y: 300, width: 1728, height: 1117)

@Test func windowsOnAMainDisplayBesideASecondScreenAreNotParked() {
    let leftHalf = CGRect(x: 0, y: 25, width: 1280, height: 1415)
    let rightHalf = CGRect(x: 1280, y: 25, width: 1280, height: 1415)
    #expect(!Geometry.looksParked(leftHalf, screens: [externalMain, laptopLeft]))
    #expect(!Geometry.looksParked(rightHalf, screens: [externalMain, laptopLeft]))
}

@Test func aLowWindowOnATallerDisplayIsNotParked() {
    // Below the laptop's bottom edge, which is not the bottom of the desktop.
    let frame = CGRect(x: 200, y: 1200, width: 800, height: 240)
    #expect(!Geometry.looksParked(frame, screens: [externalMain, laptopLeft]))
}

@Test func aParkedWindowAtTheRealSizeIsStillParked() {
    // The clamp keeps the window's full size; only a corner stays visible.
    let frame = CGRect(x: 2520, y: 1408, width: 1280, height: 1415)
    #expect(Geometry.looksParked(frame, screens: [externalMain, laptopLeft]))
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

@Test func markSideCapsAtTheMaximumOnALargeLid() {
    #expect(Geometry.markSide(fitting: CGSize(width: 200, height: 120)) == 28)
}

@Test func markSideScalesWithTheSmallerDimension() {
    // 0.6 * 40 = 24, under the 28 cap, and driven by height not width.
    #expect(Geometry.markSide(fitting: CGSize(width: 400, height: 40)) == 24)
}

@Test func markSideIsNilWhenTheLidCannotShowItLegibly() {
    #expect(Geometry.markSide(fitting: CGSize(width: 400, height: 12)) == nil)
    #expect(Geometry.markSide(fitting: .zero) == nil)
}

@Test func markSideIgnoresNegativeDimensions() {
    #expect(Geometry.markSide(fitting: CGSize(width: -100, height: 80)) == nil)
}
