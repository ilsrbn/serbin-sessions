import Foundation
import Combine

public struct PendingApproval: Identifiable {
    public let id: String
    public let sessionId: String
    public let toolName: String
    public let summary: String
    let respond: @Sendable (Reply) -> Void
}

public enum SessionState: Equatable {
    case idle
    case running(tool: String?)
    case needsApproval
    case done
}

public struct Session: Identifiable {
    public let id: String
    public var cwd: String
    public var state: SessionState = .idle
    public var lastPrompt: String?
    public var lastMessage: String?
    public var transcriptPath: String?
    public var updatedAt = Date()

    public var title: String { (cwd as NSString).lastPathComponent }
}

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [String: Session] = [:]
    @Published public private(set) var pending: [PendingApproval] = []

    public init() {}

    public var ordered: [Session] {
        sessions.values.sorted {
            if ($0.state == .needsApproval) != ($1.state == .needsApproval) { return $0.state == .needsApproval }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func handle(_ env: Envelope, respond: @escaping @Sendable (Reply) -> Void) {
        let e = env.event
        var s = sessions[e.sessionId] ?? Session(id: e.sessionId, cwd: e.cwd ?? "?")
        if let cwd = e.cwd { s.cwd = cwd }
        if let t = e.transcriptPath { s.transcriptPath = t }
        s.updatedAt = Date()

        switch e.hookEventName {
        case "SessionStart":
            s.state = .idle
        case "UserPromptSubmit":
            s.lastPrompt = e.prompt
            s.state = .running(tool: nil)
        case "PreToolUse":
            s.state = .running(tool: e.toolName)
        case "PostToolUse":
            s.state = .running(tool: nil)
        case "PermissionRequest":
            s.state = .needsApproval
            pending.append(PendingApproval(
                id: env.id, sessionId: e.sessionId, toolName: e.toolName ?? "tool",
                summary: Self.summarize(e.toolName, e.toolInput), respond: respond))
        case "Notification":
            s.lastMessage = e.message
        case "Stop", "SubagentStop":
            s.state = .done
        case "SessionEnd":
            sessions[e.sessionId] = nil
            drop(sessionId: e.sessionId, reply: .ask)
            return
        default:
            break
        }
        sessions[e.sessionId] = s
    }

    public func resolve(_ approval: PendingApproval, _ decision: Decision, message: String? = nil) {
        approval.respond(Reply(id: approval.id, decision: decision, message: message))
        pending.removeAll { $0.id == approval.id }
        if !pending.contains(where: { $0.sessionId == approval.sessionId }) {
            sessions[approval.sessionId]?.state = .running(tool: nil)
        }
    }

    private func drop(sessionId: String, reply: Decision) {
        for p in pending where p.sessionId == sessionId {
            p.respond(Reply(id: p.id, decision: reply))
        }
        pending.removeAll { $0.sessionId == sessionId }
    }

    static func summarize(_ tool: String?, _ input: JSONValue?) -> String {
        if let c = input?["command"]?.stringValue { return c }
        if let p = input?["file_path"]?.stringValue { return p }
        guard let input, let d = try? JSONEncoder().encode(input),
              let s = String(data: d, encoding: .utf8) else { return tool ?? "" }
        return String(s.prefix(400))
    }
}
