import Foundation

/// Adds/removes our hook entries in ~/.claude/settings.json (with a backup).
public enum HooksInstaller {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                "PermissionRequest", "Notification", "Stop", "SubagentStop", "SessionEnd"]
    static let marker = "notch-hook"

    public static var settingsPath: String { NSHomeDirectory() + "/.claude/settings.json" }

    /// notch-hook binary living next to the running executable (swift build output or .app bundle).
    public static func defaultHookBinary() -> String? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let p = exe.deletingLastPathComponent().appendingPathComponent("notch-hook").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    public static func isInstalled(path: String = settingsPath) -> Bool {
        let hooks = load(path)["hooks"] as? [String: Any] ?? [:]
        return events.allSatisfy { (hooks[$0] as? [Any] ?? []).contains(where: isOurs) }
    }

    public static func install(hookBinary: String, path: String = settingsPath) throws {
        var settings = load(path)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var groups = (hooks[ev] as? [Any] ?? []).filter { !isOurs($0) }
            // PermissionRequest blocks while you decide; others must stay fast.
            let timeout = ev == "PermissionRequest" ? 3600 : 5
            groups.append(["hooks": [["type": "command", "command": "\"\(hookBinary)\"", "timeout": timeout]]])
            hooks[ev] = groups
        }
        settings["hooks"] = hooks
        try save(settings, to: path)
    }

    public static func uninstall(path: String = settingsPath) throws {
        var settings = load(path)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            let kept = (hooks[ev] as? [Any] ?? []).filter { !isOurs($0) }
            hooks[ev] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try save(settings, to: path)
    }

    static func isOurs(_ group: Any) -> Bool {
        guard let g = group as? [String: Any], let hs = g["hooks"] as? [[String: Any]] else { return false }
        return hs.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    static func load(_ path: String) -> [String: Any] {
        guard let d = FileManager.default.contents(atPath: path),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    static func save(_ s: [String: Any], to path: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: path) {
            let backup = path + ".bak-serbin-sessions"
            try? fm.removeItem(atPath: backup)
            try fm.copyItem(atPath: path, toPath: backup)
        }
        let d = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys])
        try d.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
