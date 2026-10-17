import Foundation
import IslandCore

// Usage:
//   notch-hook                 hook mode: JSON on stdin (called by Claude Code)
//   notch-hook install         add hooks to ~/.claude/settings.json (backup first)
//   notch-hook uninstall       remove hooks added by install

let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
              "PermissionRequest", "Notification", "Stop", "SubagentStop", "SessionEnd"]
let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
let marker = "notch-hook"

func loadSettings() -> [String: Any] {
    guard let d = FileManager.default.contents(atPath: settingsPath),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
    return o
}

func saveSettings(_ s: [String: Any]) throws {
    if FileManager.default.fileExists(atPath: settingsPath) {
        let backup = settingsPath + ".bak-claude-island"
        try? FileManager.default.removeItem(atPath: backup)
        try FileManager.default.copyItem(atPath: settingsPath, toPath: backup)
    }
    let d = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys])
    try d.write(to: URL(fileURLWithPath: settingsPath))
}

func isOurs(_ group: Any) -> Bool {
    guard let g = group as? [String: Any], let hs = g["hooks"] as? [[String: Any]] else { return false }
    return hs.contains { ($0["command"] as? String)?.contains(marker) == true }
}

func install() throws {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    var settings = loadSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    for ev in events {
        var groups = (hooks[ev] as? [Any] ?? []).filter { !isOurs($0) }
        // Long timeout for PermissionRequest: the hook blocks while you decide.
        let timeout = ev == "PermissionRequest" ? 3600 : 5
        groups.append(["hooks": [["type": "command", "command": "\"\(exe)\"", "timeout": timeout]]])
        hooks[ev] = groups
    }
    settings["hooks"] = hooks
    try saveSettings(settings)
    print("Installed hooks for \(events.count) events -> \(settingsPath) (backup: .bak-claude-island)")
}

func uninstall() throws {
    var settings = loadSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    for ev in events {
        let kept = (hooks[ev] as? [Any] ?? []).filter { !isOurs($0) }
        hooks[ev] = kept.isEmpty ? nil : kept
    }
    settings["hooks"] = hooks.isEmpty ? nil : hooks
    try saveSettings(settings)
    print("Removed claude-island hooks")
}

func runHook() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let event = try? JSONDecoder().decode(HookEvent.self, from: input) else { exit(0) }
    let wantsReply = event.hookEventName == "PermissionRequest"
    let env = Envelope(expectsReply: wantsReply, event: event)
    // No output / exit 0 => Claude Code shows its normal dialog (app down, timeout, "ask").
    guard let reply = HookClient.send(env, wait: 3500), wantsReply,
          let out = HookOutput.permission(reply) else { exit(0) }
    print(out)
}

switch CommandLine.arguments.dropFirst().first {
case "install": do { try install() } catch { fputs("install failed: \(error)\n", stderr); exit(1) }
case "uninstall": do { try uninstall() } catch { fputs("uninstall failed: \(error)\n", stderr); exit(1) }
default: runHook()
}
