// Tests/KutuCoreTests/HotKeySpecTests.swift
import Testing
@testable import KutuCore

@Test func parsesModifierCombinations() {
    let spec = HotKeySpec.parse("alt+space")
    #expect(spec?.keyCode == 49)
    #expect(spec?.usesOption == true)
    #expect(spec?.usesCommand == false)
}

@Test func parsesMultipleModifiers() {
    let spec = HotKeySpec.parse("cmd+shift+k")
    #expect(spec?.keyCode == 40)
    #expect(spec?.usesCommand == true)
    #expect(spec?.usesShift == true)
}

@Test func rejectsUnknownKey() {
    #expect(HotKeySpec.parse("alt+nope") == nil)
}

@Test func rejectsSpecWithoutModifier() {
    #expect(HotKeySpec.parse("space") == nil)
}
