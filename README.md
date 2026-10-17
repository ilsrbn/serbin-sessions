# Claude Island

Notch panel for Claude Code sessions. Collapsed: flat black pill, current tool; an amber line + count while something needs you; "Done" for a few seconds when a run finishes. Never opens by itself.
Expanded (hover / pin / hotkey): session list, transcript, approve/deny, message input.

## Features
- Observes any Claude Code session through hooks (terminal sessions keep working as usual).
- Approve / deny tool calls from the notch (⌘Y / ⌘N). If the app is down or you answer in the terminal, the card disappears and Claude Code's normal flow takes over.
- Start sessions from the panel (`claude -p` with stream-json), send follow-ups, stop, resume past sessions.
- Transcript view (text, tool calls, results) read from `~/.claude/projects/*.jsonl`.
- Restores recently active sessions after a restart; optional tick sound (off by default, speaker button in the footer) for requests that need you. Sound and the "Done" flash are skipped while a terminal/editor is frontmost.

## Build & run
    ./scripts/bundle.sh                       # build/ClaudeIsland.app (ad-hoc signed)
    open build/ClaudeIsland.app
Then click "Install hooks" in the panel, or run `notch-hook install` (backup: `settings.json.bak-claude-island`; `notch-hook uninstall` reverts).

Dev: `swift build && .build/debug/ClaudeIsland`.

## Control from Raycast / any hotkey tool
Commands: `toggle`, `open` (focus the message box), `new` (open the New session form), `close`.
- URL: `open -g claude-island://toggle` (also launches the app if it is not running).
- CLI: `build/ClaudeIsland.app/Contents/MacOS/notch-hook toggle`.
- Raycast: add `scripts/raycast` as a Script Commands directory (Settings > Extensions > Script Commands > Add directory), then assign a hotkey to each command. Or create a Quicklink with URL `claude-island://toggle` and give it a hotkey.
- Built-in global hotkey: ⌃⌥Space (toggle).

## Layout
- `Sources/IslandCore` – protocol, unix socket, session store, transcript reader, managed host, hook installer
- `Sources/notch-hook` – CLI called by Claude Code hooks (+ install/uninstall/status)
- `Sources/ClaudeIsland` – AppKit/SwiftUI notch panel
- Tests need full Xcode (XCTest); CommandLineTools alone cannot run them.

## Notes
- `PermissionRequest` output schema verified against the official hooks docs; hooks fire in `-p` mode too, so panel-started sessions get approvals the same way. In `-p` there is no terminal fallback, so "Ask in terminal" is hidden for those.
- `AskUserQuestion` prompts cannot be answered through hooks; the card says to answer in the terminal.
- Hook timeout for `PermissionRequest` is 3600 s; all other events 5 s. App down => hook exits silently.
- `@State` is avoided on purpose (needs the SwiftUIMacros plugin from full Xcode).
- Unsigned/ad-hoc build: Gatekeeper prompt on first launch (right-click > Open). Not notarized.

## Not done
Streaming partial text (transcript refreshes every ~1.5 s while running), multi-monitor choice, launch at login, iPhone relay.
