// Tests/KutuCoreTests/LaunchCommandTests.swift
import Testing
@testable import KutuCore

@Test func itermCommandRunsInTheBoxDirectory() {
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "claude"), in: "/w/a")
    #expect(command?.executable == "/usr/bin/osascript")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(script.contains("cd '/w/a'"))
    #expect(script.contains("claude"))
}

@Test func chromeCommandPassesProfileAndURLs() {
    let command = LaunchCommand.build(
        for: AppSpec(kind: .chrome, profile: "orchard", urls: ["http://localhost:3000"]),
        in: "/w/a")
    #expect(command?.executable == "/usr/bin/open")
    #expect(command?.arguments.contains("--profile-directory=orchard") == true)
    #expect(command?.arguments.contains("http://localhost:3000") == true)
    #expect(command?.arguments.contains("-na") == true)
}

@Test func vscodeCommandOpensTheDirectory() {
    let command = LaunchCommand.build(for: AppSpec(kind: .vscode), in: "/w/a")
    #expect(command?.executable == "/usr/bin/open")
    #expect(command?.arguments == ["-a", "Visual Studio Code", "/w/a"])
}

@Test func genericAppRequiresABundleIdentifier() {
    #expect(LaunchCommand.build(for: AppSpec(kind: .app), in: "/w/a") == nil)
    let command = LaunchCommand.build(for: AppSpec(kind: .app, bundleID: "com.postmanlabs.mac"), in: "/w/a")
    #expect(command?.arguments == ["-b", "com.postmanlabs.mac"])
}

@Test func singleQuotesInPathsAreEscaped() {
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "claude"), in: "/w/it's")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(!script.contains("cd '/w/it's'"))
    #expect(script.contains("it'\\''s"))
}
