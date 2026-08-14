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
