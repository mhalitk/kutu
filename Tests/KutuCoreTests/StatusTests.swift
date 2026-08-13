// Tests/KutuCoreTests/StatusTests.swift
import Testing
import Foundation
@testable import KutuCore

private func data(_ json: String) -> Data { Data(json.utf8) }

@Test func unknownBoxHasNoStatus() {
    #expect(StatusTracker().state(forBox: "nope", directory: nil) == nil)
}

@Test func genericReporterSetsBoxStatus() {
    let tracker = StatusTracker()
    tracker.apply(StatusReport(key: "ci", scope: .box("orchard"), state: .working))
    #expect(tracker.state(forBox: "orchard", directory: nil) == .working)
}

@Test func nilStateRetractsAReporter() {
    let tracker = StatusTracker()
    tracker.apply(StatusReport(key: "ci", scope: .box("a"), state: .waiting))
    tracker.apply(StatusReport(key: "ci", scope: .box("a"), state: nil))
    #expect(tracker.state(forBox: "a", directory: nil) == nil)
}

@Test func mostUrgentReporterWins() {
    let tracker = StatusTracker()
    tracker.apply(StatusReport(key: "one", scope: .box("a"), state: .idle))
    tracker.apply(StatusReport(key: "two", scope: .box("a"), state: .working))
    tracker.apply(StatusReport(key: "three", scope: .box("a"), state: .waiting))
    #expect(tracker.state(forBox: "a", directory: nil) == .waiting)
}

@Test func directoryScopedReportCountsTowardTheBoxContainingIt() {
    let tracker = StatusTracker()
    tracker.apply(StatusReport(key: "s1", scope: .directory("/w/a/packages/web"), state: .waiting))
    #expect(tracker.state(forBox: "a", directory: "/w/a") == .waiting)
}

@Test func siblingDirectoryWithASharedPrefixIsIgnored() {
    let tracker = StatusTracker()
    tracker.apply(StatusReport(key: "s1", scope: .directory("/w/abc"), state: .waiting))
    #expect(tracker.state(forBox: "a", directory: "/w/a") == nil)
}

@Test func cliStatusMessageDecodes() {
    let report = StatusDecoder.decode(data(#"{"kutu":"status","arg":"orchard","state":"working"}"#))
    #expect(report?.scope == .box("orchard"))
    #expect(report?.state == .working)
}

@Test func claudeHookPayloadDecodesAsADirectoryScopedReport() {
    // Exactly what Claude Code writes to a hook's stdin; unknown keys ignored.
    let payload = #"{"session_id":"abc","transcript_path":"/tmp/t.jsonl","cwd":"/w/a","hook_event_name":"Notification","message":"needs permission"}"#
    let report = StatusDecoder.decode(data(payload))
    #expect(report?.key == "abc")
    #expect(report?.scope == .directory("/w/a"))
    #expect(report?.state == .waiting)
}

@Test func claudeHookEventsMapToStates() {
    // Deliberately inspects the whole report, not `report?.state`. Optional
    // chaining flattens, so "no report at all" and "a report retracting the
    // status" both collapse to the same value and become indistinguishable —
    // yet they are exactly the two cases this test exists to separate.
    func report(for event: String) -> StatusReport? {
        let json = "{\"session_id\":\"s\",\"cwd\":\"/w/a\",\"hook_event_name\":\"\(event)\"}"
        return StatusDecoder.decode(data(json))
    }
    #expect(report(for: "UserPromptSubmit")?.state == .working)
    #expect(report(for: "Stop")?.state == .idle)

    // SessionEnd yields a report whose nil state retracts the reporter.
    let ended = report(for: "SessionEnd")
    #expect(ended != nil)
    #expect(ended?.state == nil)

    // An event kutu does not care about yields no report at all.
    #expect(report(for: "PreToolUse") == nil)
}

@Test func unrelatedJSONDecodesToNothing() {
    #expect(StatusDecoder.decode(data(#"{"hello":"world"}"#)) == nil)
    #expect(StatusDecoder.decode(data("not json at all")) == nil)
}

@Test func controlMessagesAreDistinguishableFromStatusPayloads() {
    let control = try? JSONDecoder().decode(ControlMessage.self,
                                            from: data(#"{"kutu":"switch","arg":"a"}"#))
    #expect(control?.kutu == "switch")
    #expect(control?.arg == "a")
    // A Claude payload must not be mistaken for a control message.
    let claude = try? JSONDecoder().decode(
        ControlMessage.self,
        from: data(#"{"cwd":"/w/a","hook_event_name":"Stop","session_id":"s"}"#))
    #expect(claude == nil)
}
