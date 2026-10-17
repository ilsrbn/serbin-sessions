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
}
