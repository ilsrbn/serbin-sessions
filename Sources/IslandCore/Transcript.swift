import Foundation

public struct TranscriptItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case user, assistant, tool(name: String), toolResult }
    public let id: Int
    public let kind: Kind
    public let text: String
}

/// Reads the tail of a Claude Code transcript (JSONL) into displayable items.
public enum TranscriptReader {
    public static func tail(path: String, maxBytes: Int = 600_000, maxItems: Int = 120) -> [TranscriptItem] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        guard var data = try? h.readToEnd() else { return [] }
        if start > 0, let nl = data.firstIndex(of: 0x0A) { data = data.suffix(from: data.index(after: nl)) }
        var items: [TranscriptItem] = []
        var n = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            for (kind, text) in parse(obj) {
                items.append(TranscriptItem(id: n, kind: kind, text: text))
                n += 1
            }
        }
        return Array(items.suffix(maxItems)).enumerated().map {
            TranscriptItem(id: $0.offset, kind: $0.element.kind, text: $0.element.text)
        }
    }

    static func parse(_ obj: [String: Any]) -> [(TranscriptItem.Kind, String)] {
        if obj["isMeta"] as? Bool == true || obj["isSidechain"] as? Bool == true { return [] }
        guard let type = obj["type"] as? String, type == "user" || type == "assistant",
              let msg = obj["message"] as? [String: Any] else { return [] }
        var out: [(TranscriptItem.Kind, String)] = []
        if let s = msg["content"] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !t.hasPrefix("<") { out.append((type == "user" ? .user : .assistant, t)) }
            return out
        }
        for block in msg["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                let t = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !(type == "user" && t.hasPrefix("<")) { out.append((type == "user" ? .user : .assistant, t)) }
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                out.append((.tool(name: name), toolSummary(block["input"] as? [String: Any])))
            case "tool_result":
                out.append((.toolResult, String(resultText(block["content"]).prefix(300))))
            default: break
            }
        }
        return out
    }

    private static func toolSummary(_ input: [String: Any]?) -> String {
        guard let input else { return "" }
        for key in ["command", "file_path", "pattern", "url", "description", "prompt"] {
            if let v = input[key] as? String { return String(v.prefix(300)) }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: input),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return String(s.prefix(300))
    }

    private static func resultText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}

public struct RecentSession: Identifiable, Sendable {
    public let id: String
    public let cwd: String
    public let path: String
    public let modified: Date
    public let firstPrompt: String
    public var title: String { (cwd as NSString).lastPathComponent }
}

/// Finds recent sessions from ~/.claude/projects/*/*.jsonl (history + restart recovery).
public enum RecentSessions {
    public static func scan(limit: Int = 12, root: String = NSHomeDirectory() + "/.claude/projects") -> [RecentSession] {
        let fm = FileManager.default
        var files: [(String, Date)] = []
        for dir in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let d = root + "/" + dir
            for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".jsonl") {
                let p = d + "/" + f
                if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date { files.append((p, m)) }
            }
        }
        files.sort { $0.1 > $1.1 }
        return files.prefix(limit * 2).compactMap { path, mod in
            guard let h = FileHandle(forReadingAtPath: path) else { return nil }
            defer { try? h.close() }
            guard let head = try? h.read(upToCount: 128_000) else { return nil }
            var cwd: String?
            var prompt: String?
            for line in head.split(separator: 0x0A) {
                guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if cwd == nil { cwd = o["cwd"] as? String }
                if prompt == nil, let (k, t) = TranscriptReader.parse(o).first, k == .user { prompt = t }
                if cwd != nil, prompt != nil { break }
            }
            guard let cwd, let prompt else { return nil }
            let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return RecentSession(id: id, cwd: cwd, path: path, modified: mod, firstPrompt: String(prompt.prefix(120)))
        }.prefix(limit).map { $0 }
    }
}
