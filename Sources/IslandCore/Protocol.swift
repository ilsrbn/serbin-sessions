import Foundation

public enum IslandPaths {
    public static var directory: String {
        NSHomeDirectory() + "/.claude-island"
    }
    public static var socket: String { directory + "/sock" }
}

/// Payload Claude Code passes to a hook on stdin. Only fields we use.
public struct HookEvent: Codable, Sendable {
    public var sessionId: String
    public var hookEventName: String
    public var cwd: String?
    public var transcriptPath: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var message: String?
    public var prompt: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case prompt
    }

    public init(sessionId: String, hookEventName: String, cwd: String? = nil,
                transcriptPath: String? = nil, toolName: String? = nil,
                toolInput: JSONValue? = nil, message: String? = nil, prompt: String? = nil) {
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.toolInput = toolInput
        self.message = message
        self.prompt = prompt
    }
}

/// hook -> app. One JSON object per line.
public struct Envelope: Codable, Sendable {
    public var id: String
    public var expectsReply: Bool
    public var event: HookEvent

    public init(id: String = UUID().uuidString, expectsReply: Bool, event: HookEvent) {
        self.id = id
        self.expectsReply = expectsReply
        self.event = event
    }
}

public enum Decision: String, Codable, Sendable {
    case allow, deny, ask
}

/// app -> hook.
public struct Reply: Codable, Sendable {
    public var id: String
    public var decision: Decision
    public var message: String?

    public init(id: String, decision: Decision, message: String? = nil) {
        self.id = id
        self.decision = decision
        self.message = message
    }
}

public enum HookOutput {
    /// JSON for stdout of a PermissionRequest hook, or nil to fall through to the
    /// normal terminal dialog (decision == .ask).
    /// NOTE: schema taken from third-party docs; verify against code.claude.com/docs/en/hooks.
    public static func permission(_ reply: Reply) -> String? {
        guard reply.decision != .ask else { return nil }
        var decision: [String: Any] = ["behavior": reply.decision.rawValue]
        if reply.decision == .deny, let m = reply.message { decision["message"] = m }
        let obj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
