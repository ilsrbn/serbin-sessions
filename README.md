# Claude Island

Notch panel for Claude Code sessions: progress in the collapsed notch, approvals and details when expanded.

## Status
MVP stage 1 (observed sessions via hooks): socket server, `notch-hook`, session store, collapsed/expanded notch UI, approve/deny.

## Build & run
    swift build
    .build/debug/ClaudeIsland &          # start the panel
    .build/debug/notch-hook install      # add hooks to ~/.claude/settings.json (backup: settings.json.bak-claude-island)
    .build/debug/notch-hook uninstall    # remove them

Hooks fail safe: if the app is not running or times out, Claude Code shows its normal terminal dialog.

## Layout
- `Sources/IslandCore` – protocol, unix socket, session store
- `Sources/notch-hook` – CLI called by Claude Code hooks (+ install/uninstall)
- `Sources/ClaudeIsland` – AppKit/SwiftUI notch panel
- Tests need full Xcode (XCTest); CommandLineTools alone cannot run them.

## Roadmap
2. Expanded view with transcript streaming. 3. Managed sessions via Agent SDK sidecar. 4. Resume, history, settings.

## Unverified
`PermissionRequest` stdout schema (`hookSpecificOutput.decision.behavior`) comes from third-party docs; check https://code.claude.com/docs/en/hooks.
