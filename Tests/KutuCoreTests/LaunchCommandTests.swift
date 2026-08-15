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

@Test func genericAppPassesURLsThrough() {
    let command = LaunchCommand.build(
        for: AppSpec(kind: .app, urls: ["http://localhost:4321", "http://localhost:4322"], bundleID: "org.mozilla.firefox"),
        in: "/w/a")
    #expect(command?.executable == "/usr/bin/open")
    #expect(command?.arguments == ["-b", "org.mozilla.firefox", "http://localhost:4321", "http://localhost:4322"])
}

@Test func genericAppWithNoURLsIsUnchanged() {
    let command = LaunchCommand.build(for: AppSpec(kind: .app, bundleID: "org.mozilla.firefox"), in: "/w/a")
    #expect(command?.arguments == ["-b", "org.mozilla.firefox"])
}

@Test func singleQuotesInPathsAreEscaped() {
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "claude"), in: "/w/it's")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(!script.contains("cd '/w/it's'"))
    // The shell-layer escape ('\'') contains a backslash, which the outer
    // AppleScript layer then doubles so the literal decodes back to a single
    // backslash — verified against `osascript` directly. The doubled form is
    // what the generated AppleScript SOURCE actually contains.
    #expect(script.contains("it'\\\\''s"))
}

@Test func doubleQuotesCannotEscapeTheAppleScriptLiteral() {
    // A bare double quote would close the AppleScript string early and let the
    // rest be parsed as AppleScript source. The payload text still appears in
    // the script — harmlessly, inside the literal — so what must be asserted
    // is that every quote survives ESCAPED, never that the text is absent.
    let hostile = "/w/a\" & (do shell script \"echo pwned\") & \""
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "claude"), in: hostile)
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(!script.contains("a\" &"))     // would have closed the literal
    #expect(script.contains("a\\\" &"))    // escaped, so it cannot
}

@Test func aCommandKeepsItsOwnSingleQuotes() {
    // `cmd` is a shell command line, not a value inside quotes. Shell-escaping
    // it would corrupt a perfectly legitimate command.
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "say it's done"), in: "/w/a")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(script.contains("say it's done"))
}

@Test func itermWithNoCommandJustCDs() {
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm), in: "/w/a")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(script.contains("cd '/w/a'"))
    #expect(!script.contains("&&"))
}

@Test func itermWithWhitespaceOnlyCommandIsTreatedAsAbsent() {
    let command = LaunchCommand.build(for: AppSpec(kind: .iterm, cmd: "   "), in: "/w/a")
    let script = command?.arguments.joined(separator: " ") ?? ""
    #expect(script.contains("cd '/w/a'"))
    #expect(!script.contains("&&"))
}
