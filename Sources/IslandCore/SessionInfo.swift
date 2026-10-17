import Foundation

/// Model and context fill of a session, read from the last assistant turn of its transcript.
public struct SessionStats: Equatable, Sendable {
    public var model: String?
    /// Prompt size of the last request: input + cache reads + cache writes.
    public var contextTokens: Int

    /// Transcripts don't record the window. 1M-context sessions are only recognizable once they grow
    /// past 200k (or if the id says so), so that is the heuristic.
    public var contextWindow: Int {
        if contextTokens > 200_000 || model?.contains("1m") == true { return 1_000_000 }
        return 200_000
    }
    public var contextFraction: Double { min(1, Double(contextTokens) / Double(contextWindow)) }

    public init(model: String?, contextTokens: Int) {
        self.model = model
        self.contextTokens = contextTokens
    }

    /// Stats from one transcript line, or nil if it is not a main-thread assistant message with usage.
    static func parse(_ obj: [String: Any]) -> SessionStats? {
        guard obj["type"] as? String == "assistant", obj["isSidechain"] as? Bool != true,
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any] else { return nil }
        let model = msg["model"] as? String
        if model == "<synthetic>" { return nil }
        let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
        return n > 0 ? SessionStats(model: model, contextTokens: n) : nil
    }
}

public enum ModelChoice: String, CaseIterable, Sendable {
    case opus, sonnet, haiku
    public var label: String { rawValue.capitalized }
}

public enum Effort: String, CaseIterable, Sendable {
    case low, medium, high, xhigh, max
    public var label: String { self == .xhigh ? "X-High" : rawValue.capitalized }
}

/// "claude-sonnet-5-5" -> "Sonnet 5.5"; unknown ids come back unchanged.
public func friendlyModelName(_ id: String) -> String {
    let parts = id.replacingOccurrences(of: "[1m]", with: "").split(separator: "-").map(String.init)
    guard parts.first == "claude", let family = parts.dropFirst().first(where: { ModelChoice(rawValue: $0) != nil }) else { return id }
    let version = parts.drop(while: { $0 != family }).dropFirst().prefix(while: { Int($0) != nil && $0.count < 4 })
    let v = version.joined(separator: ".")
    return v.isEmpty ? family.capitalized : "\(family.capitalized) \(v)"
}

/// Plan-wide usage limits. Claude Code reports them as a `rate_limit_event` on stream-json output,
/// so they refresh whenever a panel-started session talks to the API.
public struct RateLimits: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var utilization: Double // 0...1
        public var resetsAt: Date
    }
    public var fiveHour: Window?
    public var sevenDay: Window?
    public var updatedAt: Date

    static func parse(_ obj: [String: Any]) -> RateLimits? {
        guard let info = obj["rate_limit_info"] as? [String: Any],
              let windows = info["unifiedWindows"] as? [String: Any] else { return nil }
        func window(_ key: String) -> Window? {
            guard let w = windows[key] as? [String: Any], let u = w["utilization"] as? Double,
                  let r = w["resetsAt"] as? Double else { return nil }
            return Window(utilization: u, resetsAt: Date(timeIntervalSince1970: r))
        }
        let five = window("five_hour"), seven = window("seven_day")
        return five == nil && seven == nil ? nil : RateLimits(fiveHour: five, sevenDay: seven, updatedAt: Date())
    }

    private static let key = "rateLimits"
    public static func load() -> RateLimits? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(RateLimits.self, from: $0) }
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}
