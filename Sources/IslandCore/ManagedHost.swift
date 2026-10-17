import Foundation

public enum ManagedEvent: Sendable {
    case initialized(hostId: String, sessionId: String)
    case result(hostId: String, text: String, isError: Bool)
    case exited(hostId: String, status: Int32, stderr: String)
}

public enum PermissionMode: String, CaseIterable, Sendable {
    case `default`, acceptEdits, plan
}

/// Runs `claude -p` processes with stream-json in/out so sessions can be started and driven
/// from the panel. Approvals still arrive through the PermissionRequest hook (it fires in -p mode).
public final class ManagedHost: @unchecked Sendable {
    public var onEvent: (@Sendable (ManagedEvent) -> Void)?

    private final class Proc {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        var buffer = Data()
        var errText = ""
        var stopping = false
    }

    private let lock = NSLock()
    private var procs: [String: Proc] = [:]

    public init() {}

    public static func findClaude() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let candidates = [home + "/.claude/local/claude", home + "/.local/bin/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let c = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return c }
        // GUI apps get a minimal PATH; ask a login shell.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false && fm.isExecutableFile(atPath: s!)) ? s : nil
    }

    @discardableResult
    public func start(cwd: String, prompt: String, mode: PermissionMode = .default,
                      resume: String? = nil) throws -> String {
        guard let claude = Self.findClaude() else {
            throw NSError(domain: "ClaudeIsland", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "claude CLI not found"])
        }
        let hostId = UUID().uuidString
        let p = Proc()
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json",
                    "--verbose", "--permission-mode", mode.rawValue]
        if let resume { args += ["--resume", resume] }
        p.process.executableURL = URL(fileURLWithPath: claude)
        p.process.arguments = args
        p.process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        p.process.standardInput = p.stdin
        p.process.standardOutput = p.stdout
        p.process.standardError = p.stderr

        p.stdout.fileHandleForReading.readabilityHandler = { [weak self, weak p] h in
            let d = h.availableData
            guard let self, let p, !d.isEmpty else { h.readabilityHandler = nil; return }
            self.consume(d, from: hostId, p)
        }
        p.stderr.fileHandleForReading.readabilityHandler = { [weak p] h in
            let d = h.availableData
            guard let p, !d.isEmpty else { h.readabilityHandler = nil; return }
            p.errText += String(decoding: d, as: UTF8.self)
            if p.errText.count > 4000 { p.errText = String(p.errText.suffix(4000)) }
        }
        p.process.terminationHandler = { [weak self, weak p] proc in
            guard let self, let p else { return }
            self.lock.lock(); self.procs[hostId] = nil; self.lock.unlock()
            self.onEvent?(.exited(hostId: hostId, status: p.stopping ? 0 : proc.terminationStatus, stderr: p.errText))
        }
        try p.process.run()
        lock.lock(); procs[hostId] = p; lock.unlock()
        send(hostId: hostId, text: prompt)
        return hostId
    }

    public func send(hostId: String, text: String) {
        lock.lock(); let p = procs[hostId]; lock.unlock()
        guard let p else { return }
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        guard var d = try? JSONSerialization.data(withJSONObject: msg) else { return }
        d.append(0x0A)
        try? p.stdin.fileHandleForWriting.write(contentsOf: d)
    }

    public func stop(hostId: String) {
        lock.lock(); let p = procs[hostId]; lock.unlock()
        p?.stopping = true
        p?.process.terminate()
    }

    public func stopAll() {
        lock.lock(); let all = Array(procs.keys); lock.unlock()
        all.forEach(stop)
    }

    public func isRunning(_ hostId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return procs[hostId] != nil
    }

    private func consume(_ data: Data, from hostId: String, _ p: Proc) {
        p.buffer.append(data)
        while let nl = p.buffer.firstIndex(of: 0x0A) {
            let line = p.buffer.prefix(upTo: nl)
            p.buffer = Data(p.buffer.suffix(from: p.buffer.index(after: nl)))
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = o["type"] as? String else { continue }
            if type == "system", o["subtype"] as? String == "init", let sid = o["session_id"] as? String {
                onEvent?(.initialized(hostId: hostId, sessionId: sid))
            } else if type == "result" {
                onEvent?(.result(hostId: hostId, text: o["result"] as? String ?? "",
                                 isError: o["is_error"] as? Bool ?? false))
            }
        }
    }
}
