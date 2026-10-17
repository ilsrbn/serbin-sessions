import Foundation
import IslandCore

// Usage:
//   notch-hook                 hook mode: JSON on stdin (called by Claude Code)
//   notch-hook install         add hooks to ~/.claude/settings.json (backup first)
//   notch-hook uninstall       remove hooks added by install
//   notch-hook status          print whether hooks are installed
//   notch-hook toggle|open|close|new   control the panel (bind to a hotkey in Raycast etc.)

func runHook() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let event = try? JSONDecoder().decode(HookEvent.self, from: input) else { exit(0) }
    let wantsReply = event.hookEventName == "PermissionRequest"
    let env = Envelope(expectsReply: wantsReply, event: event)
    // No output / exit 0 => Claude Code falls back to its normal flow (app down, timeout, "ask").
    guard let reply = HookClient.send(env, wait: 3500), wantsReply,
          let out = HookOutput.permission(reply) else { exit(0) }
    print(out)
}

switch CommandLine.arguments.dropFirst().first {
case "install":
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    do {
        try HooksInstaller.install(hookBinary: exe)
        print("Installed hooks -> \(HooksInstaller.settingsPath) (backup: .bak-serbin-sessions)")
    } catch { fputs("install failed: \(error)\n", stderr); exit(1) }
case "uninstall":
    do { try HooksInstaller.uninstall(); print("Removed Serbin Sessions hooks") }
    catch { fputs("uninstall failed: \(error)\n", stderr); exit(1) }
case let cmd? where IslandCommand(rawValue: cmd) != nil:
    // App not running => launch it via its URL scheme (which also carries the command).
    if !HookClient.deliver(IslandCommand(rawValue: cmd)!.envelope) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "\(IslandCommand.urlScheme)://\(cmd)"]
        try? p.run(); p.waitUntilExit()
    }
case "status":
    print(HooksInstaller.isInstalled() ? "installed" : "not installed")
default:
    runHook()
}
