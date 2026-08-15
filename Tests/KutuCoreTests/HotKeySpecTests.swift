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

@Test func rejectsSpecWhoseModifiersAreAllUnrecognised() {
    // "fn" is not a registerable Carbon modifier. Accepting it would register
    // an unmodified global Space and swallow the space bar system-wide.
    #expect(HotKeySpec.parse("fn+space") == nil)
    #expect(HotKeySpec.parse("foo+space") == nil)
}

@Test func toleratesWhitespaceAroundTokens() {
    let spec = HotKeySpec.parse(" alt + space ")
    #expect(spec?.keyCode == 49)
    #expect(spec?.usesOption == true)
}

@Test func parsesMoveHotkeyDefault() {
    let spec = HotKeySpec.parse("alt+shift+space")
    #expect(spec?.keyCode == 49)
    #expect(spec?.usesOption == true)
    #expect(spec?.usesShift == true)
    #expect(spec?.usesCommand == false)
    #expect(spec?.usesControl == false)
}
