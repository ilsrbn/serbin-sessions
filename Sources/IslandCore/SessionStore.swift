import Foundation
import Combine

/// One "don't ask again" option from Claude Code, ready to hand back as `updatedPermissions`.
public struct PermissionSuggestion: Identifiable {
    public let entry: JSONValue
    public let label: String
    public var id: String { label }

    init?(_ entry: JSONValue) {
        guard let type = entry["type"]?.stringValue else { return nil }
        self.entry = entry
        let scope: String = switch entry["destination"]?.stringValue {
        case "session": "this session"
        case "localSettings": "this project, just me"
        case "projectSettings": "this project, shared"
        case "userSettings": "all projects"
        default: "from now on"
        }
        switch type {
        case "addRules":
            var rules: [String] = []
            if case .array(let rs)? = entry["rules"] {
                rules = rs.compactMap { r in
                    guard let t = r["toolName"]?.stringValue else { return nil }
                    if let c = r["ruleContent"]?.stringValue { return "\(t)(\(c))" }
                    return t
                }
            }
            label = "\(rules.joined(separator: ", ")) · \(scope)"
        case "setMode": label = "Switch to \(entry["mode"]?.stringValue ?? "mode") · \(scope)"
        case "addDirectories": label = "Allow this directory · \(scope)"
        default: return nil
        }
    }
}

public struct PendingApproval: Identifiable {
    public let id: String
    public let sessionId: String
    public let toolName: String
    public let summary: String
    /// Tools the hook cannot answer (e.g. AskUserQuestion) must be handled in the terminal.
    public let terminalOnly: Bool
    public let suggestions: [PermissionSuggestion]
    let channel: ReplyChannel
}

public enum SessionState: Equatable {
    case idle
    case running(tool: String?)
    case needsApproval
    case needsInput(String)
    case done
    case failed(String)
}

public struct Session: Identifiable {
    public var id: String
    public var cwd: String
    public var state: SessionState = .idle
    public var lastPrompt: String?
    public var lastMessage: String?
    public var transcriptPath: String?
    public var updatedAt = Date()
    /// Set while a panel-started `claude -p` process is attached.
    public var hostId: String?
    /// Terminal session closed (SessionEnd) or only known from history. Safe to resume.
    public var ended = false
    /// Model and context fill from the transcript.
    public var stats: SessionStats?
    /// What the next panel-started run will use. Effort is not recorded in transcripts, so it is only
    /// known for sessions started (or resumed) here.
    public var model: ModelChoice?
    public var effort: Effort?
    /// What the attached `-p` process was started with.
    var runModel: ModelChoice?
    var runEffort: Effort?

    public var isManaged: Bool { hostId != nil }
    public var title: String { (cwd as NSString).lastPathComponent }
}

@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [String: Session] = [:]
    @Published public private(set) var pending: [PendingApproval] = []
    @Published public private(set) var transcripts: [String: [TranscriptItem]] = [:]
    @Published public var lastError: String?
    @Published public private(set) var rateLimits: RateLimits? = RateLimits.load()

    private let host = ManagedHost()
    private var refreshing: Set<String> = []

    public init() {
        host.onEvent = { [weak self] e in
            Task { @MainActor in self?.handleManaged(e) }
        }
    }

    public var ordered: [Session] {
        sessions.values.sorted {
            if $0.state.urgency != $1.state.urgency { return $0.state.urgency > $1.state.urgency }
            return $0.updatedAt > $1.updatedAt
        }
    }

    // MARK: Hook events

    public func handle(_ env: Envelope, channel: ReplyChannel) {
        let e = env.event
        var s = sessions[e.sessionId] ?? Session(id: e.sessionId, cwd: e.cwd ?? "?")
        if let cwd = e.cwd { s.cwd = cwd }
        if let t = e.transcriptPath { s.transcriptPath = t }
        s.updatedAt = Date()
        if e.hookEventName != "SessionEnd" { s.ended = false }

        switch e.hookEventName {
        case "SessionStart":
            if s.state == .idle || s.state == .done { s.state = .idle }
        case "UserPromptSubmit":
            s.lastPrompt = e.prompt
            s.state = .running(tool: nil)
        case "PreToolUse":
            s.state = .running(tool: e.toolName)
        case "PostToolUse":
            if s.state != .needsApproval { s.state = .running(tool: nil) }
        case "PermissionRequest":
            s.state = .needsApproval
            let approval = PendingApproval(
                id: env.id, sessionId: e.sessionId, toolName: e.toolName ?? "tool",
                summary: Self.summarize(e.toolName, e.toolInput),
                terminalOnly: e.toolName == "AskUserQuestion",
                suggestions: Self.suggestions(e.permissionSuggestions), channel: channel)
            pending.append(approval)
            channel.onCancel { [weak self] in
                Task { @MainActor in self?.cancel(approvalId: approval.id) }
            }
        case "Notification":
            // idle_prompt just means "Claude finished and has been idle"; it is not a question.
            // Only real dialogs (elicitation / agent asking) count as needing you.
            if let m = e.message { s.lastMessage = m }
            switch e.notificationType ?? "" {
            case "elicitation_dialog", "agent_needs_input":
                s.state = .needsInput(e.message ?? e.notificationType ?? "input requested")
            case "idle_prompt":
                if case .running = s.state { s.state = .done }
            default: break
            }
        case "Stop", "SubagentStop":
            if e.hookEventName == "Stop" {
                s.state = .done
                if let m = e.lastAssistantMessage { s.lastMessage = m }
            }
        case "SessionEnd":
            // Keep it in the list (as history) so it can be reopened/resumed later.
            s.ended = true
            s.state = .done
            for p in pending where p.sessionId == e.sessionId { p.channel.send(Reply(id: p.id, decision: .ask)) }
            pending.removeAll { $0.sessionId == e.sessionId }
        default:
            break
        }
        sessions[e.sessionId] = s
        prune()
        refreshTranscript(e.sessionId)
    }

    /// The terminal dialog was answered (hooks give no signal for that), so drop the flag by hand.
    public func dismiss(_ sessionId: String) {
        if case .needsInput = sessions[sessionId]?.state { sessions[sessionId]?.state = .done }
    }

    /// `remember` is one of `approval.suggestions`; it is applied by Claude Code together with the allow.
    public func resolve(_ approval: PendingApproval, _ decision: Decision, message: String? = nil,
                        remember: PermissionSuggestion? = nil) {
        approval.channel.send(Reply(id: approval.id, decision: decision, message: message,
                                    updatedPermissions: remember.map { .array([$0.entry]) }))
        pending.removeAll { $0.id == approval.id }
        settle(sessionId: approval.sessionId)
    }

    private func cancel(approvalId: String) {
        guard let p = pending.first(where: { $0.id == approvalId }) else { return }
        pending.removeAll { $0.id == approvalId }
        settle(sessionId: p.sessionId)
    }

    private func settle(sessionId: String) {
        if !pending.contains(where: { $0.sessionId == sessionId }), sessions[sessionId]?.state == .needsApproval {
            sessions[sessionId]?.state = .running(tool: nil)
        }
    }

    // MARK: Transcripts

    public func refreshTranscript(_ sessionId: String) {
        guard let path = sessions[sessionId]?.transcriptPath, !refreshing.contains(sessionId) else { return }
        refreshing.insert(sessionId)
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000) // debounce bursts of events
            let (items, stats) = TranscriptReader.read(path: path)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.refreshing.remove(sessionId)
                if self.transcripts[sessionId] != items { self.transcripts[sessionId] = items }
                if let stats, self.sessions[sessionId]?.stats != stats { self.sessions[sessionId]?.stats = stats }
            }
        }
    }

    /// Re-read transcripts of running sessions (hooks do not fire while the model streams text).
    public func tick() {
        for (id, s) in sessions { if case .running = s.state { refreshTranscript(id) } }
    }

    /// Restart recovery: load recent sessions from ~/.claude/projects as history (no age cutoff).
    public func recover(limit: Int = 20) {
        for r in RecentSessions.scan(limit: limit) {
            guard sessions[r.id] == nil else { continue }
            var s = Session(id: r.id, cwd: r.cwd)
            s.state = .done
            s.ended = true
            s.lastPrompt = r.firstPrompt
            s.transcriptPath = r.path
            s.updatedAt = r.modified
            sessions[r.id] = s
            refreshTranscript(r.id)
        }
        prune()
    }

    /// Keep the sidebar bounded: drop the oldest idle history entries beyond `maxSessions`.
    private func prune(maxSessions: Int = 30) {
        guard sessions.count > maxSessions else { return }
        let droppable = sessions.values
            .filter { $0.hostId == nil && ($0.state == .done || $0.state == .idle) }
            .sorted { $0.updatedAt < $1.updatedAt }
        for s in droppable.prefix(sessions.count - maxSessions) {
            sessions[s.id] = nil
            transcripts[s.id] = nil
        }
    }

    // MARK: Managed sessions

    public func startManaged(cwd: String, prompt: String, mode: PermissionMode, resume: String? = nil,
                             model: ModelChoice? = nil, effort: Effort? = nil) {
        do {
            let hostId = try host.start(cwd: cwd, prompt: prompt, mode: mode, resume: resume,
                                        model: model, effort: effort)
            var s = Session(id: resume ?? "starting-\(hostId)", cwd: cwd)
            s.hostId = hostId
            s.model = model
            s.effort = effort
            s.runModel = model
            s.runEffort = effort
            s.lastPrompt = prompt
            s.state = .running(tool: nil)
            if let resume, let old = sessions[resume] {
                s.transcriptPath = old.transcriptPath
                s.stats = old.stats
            }
            sessions[s.id] = s
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func send(_ text: String, to sessionId: String) {
        guard let s = sessions[sessionId], let hostId = s.hostId else { return }
        if s.model != s.runModel || s.effort != s.runEffort {
            host.stop(hostId: hostId)
            sessions[sessionId]?.hostId = nil // its .exited is ignored from here on
            startManaged(cwd: s.cwd, prompt: text, mode: .default, resume: sessionId, model: s.model, effort: s.effort)
            return
        }
        host.send(hostId: hostId, text: text)
        sessions[sessionId]?.state = .running(tool: nil)
        sessions[sessionId]?.lastPrompt = text
    }

    /// Remembers the choice. It applies to the next message: a running `-p` process cannot change
    /// model or effort, so `send` restarts it with `--resume` when they differ from what it was started with.
    public func configure(_ sessionId: String, model: ModelChoice?, effort: Effort?) {
        sessions[sessionId]?.model = model
        sessions[sessionId]?.effort = effort
    }

    /// Start or resume with whatever model / effort the session is configured for.
    public func resume(_ sessionId: String, prompt: String) {
        guard let s = sessions[sessionId] else { return }
        startManaged(cwd: s.cwd, prompt: prompt, mode: .default, resume: sessionId, model: s.model, effort: s.effort)
    }

    public func stop(_ sessionId: String) {
        if let h = sessions[sessionId]?.hostId { host.stop(hostId: h) }
    }

    public func stopAllManaged() { host.stopAll() }

    private func sessionId(forHost hostId: String) -> String? {
        sessions.first(where: { $0.value.hostId == hostId })?.key
    }

    private func handleManaged(_ e: ManagedEvent) {
        switch e {
        case .rateLimits(let r):
            rateLimits = r
            r.save()
        case .initialized(let hostId, let sid, let model):
            guard let tmp = sessionId(forHost: hostId) else { return }
            var s = sessions[tmp]!
            if let model { s.stats = SessionStats(model: model, contextTokens: s.stats?.contextTokens ?? 0) }
            if tmp != sid {
                sessions[tmp] = nil
                if let hooked = sessions[sid] { // hook SessionStart arrived first
                    s.transcriptPath = hooked.transcriptPath ?? s.transcriptPath
                    s.state = hooked.state
                }
                s.id = sid
            }
            sessions[sid] = s
            refreshTranscript(sid)
        case .result(let hostId, let text, let isError):
            guard let id = sessionId(forHost: hostId) else { return }
            sessions[id]?.state = isError ? .failed(text) : .done
            if !text.isEmpty { sessions[id]?.lastMessage = text }
            sessions[id]?.updatedAt = Date()
            refreshTranscript(id)
        case .exited(let hostId, let status, let err):
            guard let id = sessionId(forHost: hostId) else { return }
            sessions[id]?.hostId = nil
            if status != 0 {
                let tail = err.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)
                sessions[id]?.state = .failed(tail.isEmpty ? "claude exited (\(status))" : String(tail))
            } else if case .running = sessions[id]?.state {
                sessions[id]?.state = .done
            }
            for p in pending where p.sessionId == id { p.channel.send(Reply(id: p.id, decision: .ask)) }
            pending.removeAll { $0.sessionId == id }
        }
    }

    static func suggestions(_ raw: JSONValue?) -> [PermissionSuggestion] {
        guard case .array(let items)? = raw else { return [] }
        return items.compactMap(PermissionSuggestion.init)
    }

    static func summarize(_ tool: String?, _ input: JSONValue?) -> String {
        if let c = input?["command"]?.stringValue { return c }
        if let p = input?["file_path"]?.stringValue { return p }
        guard let input, let d = try? JSONEncoder().encode(input),
              let s = String(data: d, encoding: .utf8) else { return tool ?? "" }
        return String(s.prefix(400))
    }
}

extension SessionState {
    public var urgency: Int {
        switch self {
        case .needsApproval: 5
        case .needsInput: 4
        case .failed: 3
        case .running: 2
        case .done: 1
        case .idle: 0
        }
    }
}
