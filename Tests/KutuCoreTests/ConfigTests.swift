// Tests/KutuCoreTests/ConfigTests.swift
import Testing
import Foundation
@testable import KutuCore

@Test func parsesGlobalConfig() throws {
    let cfg = try KutuConfig.parse("""
    hotkey = "alt+space"
    pinned = ["com.spotify.client"]

    [[box]]
    name = "orchard"
    dir = "~/workspace/orchard"

    [[box]]
    name = "halit-ca"
    dir = "~/workspace/halit.ca"
    """)
    #expect(cfg.hotkey == "alt+space")
    #expect(cfg.pinnedBundleIDs == ["com.spotify.client"])
    #expect(cfg.boxes.count == 2)
    #expect(cfg.boxes[0].name == "orchard")
    #expect(cfg.boxes[0].dir.hasSuffix("/workspace/orchard"))
    #expect(!cfg.boxes[0].dir.hasPrefix("~"))
}

@Test func emptyConfigUsesDefaults() throws {
    let cfg = try KutuConfig.parse("")
    #expect(cfg.hotkey == "alt+space")
    #expect(cfg.boxes.isEmpty)
    #expect(cfg.pinnedBundleIDs.isEmpty)
}

@Test func boxMissingRequiredFieldIsSkipped() throws {
    let cfg = try KutuConfig.parse("""
    [[box]]
    name = "no-dir"
    """)
    #expect(cfg.boxes.isEmpty)
}

@Test func cmdTabDefaultsToNotify() throws {
    let cfg = try KutuConfig.parse("")
    #expect(cfg.cmdTab == .notify)
}

@Test func cmdTabSwitchIsParsed() throws {
    let cfg = try KutuConfig.parse("""
    cmd_tab = "switch"
    """)
    #expect(cfg.cmdTab == .switch)
}

@Test func cmdTabUnrecognisedValueFallsBackToNotify() throws {
    let cfg = try KutuConfig.parse("""
    cmd_tab = "nonsense"
    """)
    #expect(cfg.cmdTab == .notify)
}

@Test func parsesBoxManifest() throws {
    let m = try BoxManifest.parse("""
    name = "orchard"

    [[app]]
    kind = "iterm"
    cmd = "claude"

    [[app]]
    kind = "chrome"
    profile = "orchard"
    urls = ["http://localhost:3000"]

    [[app]]
    kind = "vscode"
    """)
    #expect(m.name == "orchard")
    #expect(m.apps.count == 3)
    #expect(m.apps[0].kind == .iterm)
    #expect(m.apps[0].cmd == "claude")
    #expect(m.apps[1].kind == .chrome)
    #expect(m.apps[1].profile == "orchard")
    #expect(m.apps[1].urls == ["http://localhost:3000"])
    #expect(m.apps[2].kind == .vscode)
    #expect(m.apps[2].urls.isEmpty)
}

@Test func unknownAppKindIsSkipped() throws {
    let m = try BoxManifest.parse("""
    name = "x"

    [[app]]
    kind = "emacs"
    """)
    #expect(m.apps.isEmpty)
}
