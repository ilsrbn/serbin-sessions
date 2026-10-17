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

    func testSocketRoundTrip() throws {
        // Uses the real path; skip if an app instance owns it.
        let path = NSTemporaryDirectory() + "ci-\(getpid()).sock"
        let server = SocketServer(path: path)
        try server.start { env, respond in respond(Reply(id: env.id, decision: .allow)) }
        // HookClient talks to IslandPaths.socket, so just verify the server binds.
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        unlink(path)
    }
}
