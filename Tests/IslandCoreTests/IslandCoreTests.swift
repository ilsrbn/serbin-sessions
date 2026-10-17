import XCTest
@testable import IslandCore

final class IslandCoreTests: XCTestCase {
    func testDecodePermissionRequest() throws {
        let json = #"""
        {"session_id":"s1","hook_event_name":"PermissionRequest","cwd":"/tmp/p",
         "tool_name":"Bash","tool_input":{"command":"ls -la"}}
        """#
        let e = try JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
        XCTAssertEqual(e.toolName, "Bash")
        XCTAssertEqual(SessionStore.summarize(e.toolName, e.toolInput), "ls -la")
    }

    func testAskProducesNoOutput() {
        XCTAssertNil(HookOutput.permission(Reply(id: "1", decision: .ask)))
        XCTAssertNotNil(HookOutput.permission(Reply(id: "1", decision: .allow)))
    }

    func testTranscriptParse() {
        let obj: [String: Any] = ["type": "assistant", "message": ["role": "assistant", "content": [
            ["type": "text", "text": "hello"],
            ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]]]]]
        let r = TranscriptReader.parse(obj)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].1, "hello")
        XCTAssertEqual(r[1].0, .tool(name: "Bash"))
    }

    func testInstallerRoundTrip() throws {
        let path = NSTemporaryDirectory() + "settings-\(getpid()).json"
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other"}]}]}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        try HooksInstaller.install(hookBinary: "/x/notch-hook", path: path)
        XCTAssertTrue(HooksInstaller.isInstalled(path: path))
        try HooksInstaller.uninstall(path: path)
        XCTAssertFalse(HooksInstaller.isInstalled(path: path))
        let left = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(left.contains("other"))
    }

    func testStatsAndNames() {
        let obj: [String: Any] = ["type": "assistant", "message": ["model": "claude-sonnet-5-5", "content": [],
            "usage": ["input_tokens": 2, "cache_read_input_tokens": 39507, "cache_creation_input_tokens": 19512]]]
        let st = SessionStats.parse(obj)
        XCTAssertEqual(st?.contextTokens, 59021)
        XCTAssertEqual(st?.contextWindow, 200_000)
        XCTAssertEqual(friendlyModelName("claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(friendlyModelName("claude-haiku-5-5"), "Haiku 5.5")
    }

    func testRateLimitParse() {
        let obj: [String: Any] = ["type": "rate_limit_event", "rate_limit_info": ["unifiedWindows": [
            "five_hour": ["utilization": 0.77, "resetsAt": 1792263600.0],
            "seven_day": ["utilization": 0.08, "resetsAt": 1792818000.0]]]]
        let r = RateLimits.parse(obj)
        XCTAssertEqual(r?.fiveHour?.utilization, 0.77)
        XCTAssertNotNil(r?.sevenDay)
    }
}
