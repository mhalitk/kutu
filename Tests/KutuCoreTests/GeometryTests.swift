// Tests/KutuCoreTests/GeometryTests.swift
import Testing
import CoreGraphics
@testable import KutuCore

private let mainScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
private let secondScreen = CGRect(x: 579, y: -1117, width: 1728, height: 1117)

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
