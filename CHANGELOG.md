# Changelog

## 0.1.0 · 2026-10-18

First working build.

- Notch pill with three quiet states: working, needs you (amber line and count), done.
- Approve or deny tool calls from the notch (⌘Y / ⌘N), with "always allow" suggestions.
- Start, steer, stop and resume sessions from the panel (`claude -p`, stream-json).
- Transcript with block markdown, tool calls and results.
- Session info: model, effort, context fill; plan limits (5h / 7d).
- Control from Raycast, the `serbin-sessions://` URL scheme or `notch-hook`; global hotkey ⌃⌥Space.
- Launch at login, optional tick sound, history of recent sessions.
- Rebrand from Claude Island to Serbin Sessions.
