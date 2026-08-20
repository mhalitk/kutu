// Tests/KutuCoreTests/BoxRegistrationTests.swift
import Testing
import Foundation
@testable import KutuCore

@Test func emptyConfigAppends() {
    let outcome = BoxRegistration.plan(existing: KutuConfig(), name: "orchard", dir: "~/workspace/orchard")
    guard case .append(let block) = outcome else {
        Issue.record("expected .append, got \(outcome)")
        return
    }
    #expect(block.hasPrefix("\n[[box]]\n"))
    #expect(block.contains("name = \"orchard\""))
    #expect(block.contains("dir  = \"~/workspace/orchard\""))
}

@Test func sameNameSameDirIsAlreadyRegistered() {
    let existing = KutuConfig(boxes: [BoxSpec(name: "orchard", dir: "/Users/x/workspace/orchard")])
    let outcome = BoxRegistration.plan(existing: existing, name: "orchard", dir: "/Users/x/workspace/orchard")
    #expect(outcome == .alreadyRegistered)
}

@Test func trailingSlashMismatchIsStillAlreadyRegistered() {
    let existing = KutuConfig(boxes: [BoxSpec(name: "orchard", dir: "/Users/x/workspace/orchard/")])
    let outcome = BoxRegistration.plan(existing: existing, name: "orchard", dir: "/Users/x/workspace/orchard")
    #expect(outcome == .alreadyRegistered)

    let existing2 = KutuConfig(boxes: [BoxSpec(name: "orchard", dir: "/Users/x/workspace/orchard")])
    let outcome2 = BoxRegistration.plan(existing: existing2, name: "orchard", dir: "/Users/x/workspace/orchard/")
    #expect(outcome2 == .alreadyRegistered)
}

@Test func sameNameDifferentDirIsAConflict() {
    let existing = KutuConfig(boxes: [BoxSpec(name: "orchard", dir: "/Users/x/workspace/orchard")])
    let outcome = BoxRegistration.plan(existing: existing, name: "orchard", dir: "/Users/x/other/orchard")
    #expect(outcome == .conflict(existingDir: "/Users/x/workspace/orchard"))
}

@Test func differentNameSameDirAppends() {
    let existing = KutuConfig(boxes: [BoxSpec(name: "orchard", dir: "/Users/x/workspace/orchard")])
    let outcome = BoxRegistration.plan(existing: existing, name: "orchard-2", dir: "/Users/x/workspace/orchard")
    guard case .append = outcome else {
        Issue.record("expected .append, got \(outcome)")
        return
    }
}

@Test func displayPathUsesTildeUnderHome() {
    #expect(BoxRegistration.displayPath("/Users/x/workspace/orchard", home: "/Users/x") == "~/workspace/orchard")
    #expect(BoxRegistration.displayPath("/Users/x", home: "/Users/x") == "~")
    #expect(BoxRegistration.displayPath("/opt/orchard", home: "/Users/x") == "/opt/orchard")
}

// A box name reaches `plan` straight from a repo's kutu.toml, and the block it
// returns is appended verbatim to the user's global boxes.toml. Anything that
// would need escaping inside a TOML basic string is therefore refused, so the
// interpolation cannot be broken out of.

@Test func nameContainingAQuoteIsRefused() {
    let outcome = BoxRegistration.plan(existing: KutuConfig(),
                                       name: "innocent\"\ndir = \"/tmp/attacker\"\n[[box]]\nname = \"backdoor",
                                       dir: "~/code/thing")
    guard case .invalid = outcome else {
        Issue.record("expected .invalid, got \(outcome)")
        return
    }
}

@Test func nameContainingABackslashOrControlCharacterIsRefused() {
    for name in ["back\\slash", "tab\there", "bell\u{07}"] {
        guard case .invalid = BoxRegistration.plan(existing: KutuConfig(), name: name, dir: "~/x") else {
            Issue.record("expected .invalid for \(name)")
            return
        }
    }
}

@Test func directoryContainingAQuoteIsRefused() {
    // macOS permits a quote in a filename, so a repo cloned into one would
    // otherwise inject through `dir` instead of `name`.
    let outcome = BoxRegistration.plan(existing: KutuConfig(), name: "fine",
                                       dir: "~/code/od\"d")
    guard case .invalid = outcome else {
        Issue.record("expected .invalid, got \(outcome)")
        return
    }
}

@Test func emptyNameIsRefused() {
    guard case .invalid = BoxRegistration.plan(existing: KutuConfig(), name: "", dir: "~/x") else {
        Issue.record("expected .invalid")
        return
    }
}

@Test func nonASCIINamesAreStillAccepted() {
    // The rule is about TOML escaping, not about being English.
    guard case .append(let block) = BoxRegistration.plan(existing: KutuConfig(),
                                                         name: "müşteri", dir: "~/code/müşteri") else {
        Issue.record("expected .append")
        return
    }
    #expect(block.contains("name = \"müşteri\""))
}
