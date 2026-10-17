import Foundation

public enum IslandPaths {
    public static var directory: String {
        NSHomeDirectory() + "/.serbin-sessions"
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
    public var notificationType: String?
    public var lastAssistantMessage: String?
    /// PermissionRequest only: the "don't ask again" options Claude Code would offer in its own dialog.
    public var permissionSuggestions: JSONValue?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case message
        case prompt
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case permissionSuggestions = "permission_suggestions"
    }

    public init(sessionId: String, hookEventName: String, cwd: String? = nil,
                transcriptPath: String? = nil, toolName: String? = nil,
                toolInput: JSONValue? = nil, message: String? = nil, prompt: String? = nil,
                notificationType: String? = nil, lastAssistantMessage: String? = nil,
                permissionSuggestions: JSONValue? = nil) {
        self.sessionId = sessionId
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.toolInput = toolInput
        self.message = message
        self.prompt = prompt
        self.notificationType = notificationType
        self.lastAssistantMessage = lastAssistantMessage
        self.permissionSuggestions = permissionSuggestions
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
    /// allow only: permission update entries to apply (e.g. an "always allow" rule).
    public var updatedPermissions: JSONValue?

    public init(id: String, decision: Decision, message: String? = nil, updatedPermissions: JSONValue? = nil) {
        self.id = id
        self.decision = decision
        self.message = message
        self.updatedPermissions = updatedPermissions
    }
}

public enum HookOutput {
    /// JSON for stdout of a PermissionRequest hook, or nil to fall through to the
    /// normal terminal dialog (decision == .ask).
    /// Schema verified against code.claude.com/docs/en/hooks (hookSpecificOutput.decision.behavior).
    public static func permission(_ reply: Reply) -> String? {
        guard reply.decision != .ask else { return nil }
        var decision: [String: Any] = ["behavior": reply.decision.rawValue]
        if reply.decision == .deny, let m = reply.message { decision["message"] = m }
        if reply.decision == .allow, let u = reply.updatedPermissions,
           let d = try? JSONEncoder().encode(u), let o = try? JSONSerialization.jsonObject(with: d) {
            decision["updatedPermissions"] = o
        }
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

/// Remote control of the panel (CLI, URL scheme, Raycast). Travels over the hook socket as an
/// event named "island.<command>".
public enum IslandCommand: String, CaseIterable, Sendable {
    case toggle, open, close, new

    public static let eventPrefix = "island."
    public static let urlScheme = "serbin-sessions"
    /// Pre-rename scheme, still accepted so old Quicklinks keep working.
    public static let legacyUrlScheme = "claude-island"

    public var envelope: Envelope {
        Envelope(expectsReply: false, event: HookEvent(sessionId: "-", hookEventName: Self.eventPrefix + rawValue))
    }

    public init?(eventName: String) {
        guard eventName.hasPrefix(Self.eventPrefix) else { return nil }
        self.init(rawValue: String(eventName.dropFirst(Self.eventPrefix.count)))
    }
}
