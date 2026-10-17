import AppKit
import SwiftUI
import Combine
import IslandCore
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let store = SessionStore()
    @MainActor private let ui = NotchUIState()
    private let server = SocketServer()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var hotKey: HotKey?
    private var insideSince: Date?
    private var outsideSince: Date?
    /// After an explicit close the cursor may still rest on the notch; hover stays off until it leaves.
    private var hoverNeedsExit = false

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = self.store, ui = self.ui
        let panel = NotchPanel(store: store, ui: ui)
        self.panel = panel
        panel.reposition(expanded: false)
        panel.orderFrontRegardless()

        // Resize the panel whenever anything that affects expansion changes.
        ui.objectWillChange.map { _ in }
            .merge(with: store.$pending.map { _ in })
            .receive(on: RunLoop.main)
            .sink { [weak panel] in
                ui.recompute()
                panel?.reposition(expanded: ui.expanded)
            }
            .store(in: &cancellables)

        // Panel lost key status (click on another window, Cmd-Tab, Esc): stop "typing" so it can
        // collapse, and drop the new-session form unless pinned. Never steal focus back.
        let lostFocus = { [weak panel] in
            guard let panel, !panel.inSummonGrace else { return }
            ui.typing = false
            if !ui.pinned { ui.showingNew = false }
        }
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { _ in MainActor.assumeIsolated { lostFocus() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { _ in MainActor.assumeIsolated { lostFocus() } }
            .store(in: &cancellables)

        // After the last approval is answered the panel collapses; hand focus back to the app below.
        store.$pending.map(\.isEmpty).removeDuplicates().filter { $0 }.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.ui.typing, !self.ui.pinned, !self.ui.showingNew else { return }
                    self.panel?.releaseFocus()
                }
            }
            .store(in: &cancellables)

        // Esc closes the panel; focus simply returns to the app underneath.
        panel.onEscape = { [weak self] in MainActor.assumeIsolated { self?.perform(.close) } }
        ui.$closeRequest.dropFirst()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.perform(.close) } }
            .store(in: &cancellables)

        // Global hotkey: ⌃⌥Space opens the panel with the composer focused (again: closes it).
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            MainActor.assumeIsolated { self?.perform(.toggle) }
        }

        // Quiet signals. A run finishing flashes the pill for a few seconds; a new request that needs
        // you plays an opt-in tick. Both stay silent while a terminal/editor is frontmost, since you
        // are probably already looking at the session (heuristic: the app, not the exact tab).
        store.$sessions.map { $0.mapValues(\.state) }
            .scan(([String: SessionState](), [String: SessionState]())) { ($0.1, $1) }
            .receive(on: RunLoop.main)
            .sink { old, new in
                MainActor.assumeIsolated {
                    guard !Self.terminalInFront else { return }
                    for (id, st) in new where st == .done && old[id]?.isRunning == true {
                        if let title = store.sessions[id]?.title { ui.flashDone(title) }
                    }
                }
            }
            .store(in: &cancellables)

        // The edge light sweeps in when something starts needing you.
        store.$pending.map { _ in () }.merge(with: store.$sessions.map { _ in () })
            .receive(on: RunLoop.main)
            .map { MainActor.assumeIsolated { store.urgentCount > 0 } }
            .removeDuplicates().filter { $0 }
            .sink { _ in MainActor.assumeIsolated { ui.urgentStart = Date() } }
            .store(in: &cancellables)

        store.$pending
            .map(\.count).removeDuplicates().scan((0, 0)) { ($0.1, $1) }
            .filter { $0.1 > $0.0 }
            .sink { _ in
                MainActor.assumeIsolated {
                    if ui.soundEnabled && !Self.terminalInFront { NSSound(named: "Tink")?.play() }
                }
            }
            .store(in: &cancellables)

        store.recover()

        // Hover is polled from the global mouse position instead of SwiftUI onHover: resizing the
        // window changes what is under the cursor, which made onHover flicker open/closed.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollHover() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in store.tick() }
        }

        do {
            try server.start { [weak self] env, channel in
                Task { @MainActor in
                    if let cmd = IslandCommand(eventName: env.event.hookEventName) { self?.perform(cmd) }
                    else { store.handle(env, channel: channel) }
                }
            }
        } catch {
            NSLog("serbin-sessions: socket start failed: \(error)")
            NSApp.terminate(nil)
        }
    }

    private static let terminalBundles: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.jetbrains.intellij", "dev.zed.Zed",
    ]

    private static var terminalInFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(terminalBundles.contains) ?? false
    }

    /// Panel control shared by the global hotkey, `notch-hook <cmd>` and serbin-sessions:// URLs.
    @MainActor
    func perform(_ cmd: IslandCommand) {
        guard let panel else { return }
        switch cmd {
        case .toggle: perform(panel.holdsFocus ? .close : .open)
        case .open: panel.summon(ui)
        case .new:
            ui.showingNew = true
            panel.summon(ui)
        case .close:
            ui.typing = false; ui.pinned = false; ui.showingNew = false; ui.hovering = false; ui.peeking = false
            hoverNeedsExit = true
            panel.releaseFocus()
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where [IslandCommand.urlScheme, IslandCommand.legacyUrlScheme].contains(u.scheme ?? "") {
            if let cmd = IslandCommand(rawValue: u.host ?? u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
                perform(cmd)
            }
        }
    }

    @MainActor
    private func pollHover() {
        guard let panel else { return }
        let m = NSEvent.mouseLocation
        let now = Date()
        if ui.hovering {
            ui.peeking = false
            // Stay open while the cursor is anywhere over the expanded panel (plus a margin).
            let keep = panel.rect(expanded: true)?.insetBy(dx: -12, dy: -12)
            if keep?.contains(m) == true { outsideSince = nil; return }
            let since = outsideSince ?? now
            outsideSince = since
            if now.timeIntervalSince(since) > 0.4 { ui.hovering = false; outsideSince = nil }
        } else {
            // Open after a short dwell on the collapsed notch area.
            let wide = ui.peeking || store.urgentCount > 0
            let trigger = panel.collapsedRect(wide: wide, baseWidth: ui.baseWidth)?.insetBy(dx: -6, dy: -4).offsetBy(dx: 0, dy: -2)
            let inside = trigger.map { $0.contains(m) || m.y >= $0.maxY - 1 && abs(m.x - $0.midX) < $0.width / 2 } ?? false
            if hoverNeedsExit {
                if !inside { hoverNeedsExit = false }
                return
            }
            // Two stages: a short rest on the notch slides the ears out (peek), a longer one opens the panel.
            if inside {
                let since = insideSince ?? now
                insideSince = since
                let dwell = now.timeIntervalSince(since)
                if dwell > 0.1, !ui.peeking { ui.peeking = true }
                if dwell > 0.4 { ui.hovering = true; ui.peeking = false; insideSince = nil }
            } else {
                insideSince = nil
                if ui.peeking { ui.peeking = false }
            }
        }
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        store.stopAllManaged()
    }
}

/// Minimal Carbon global hotkey (needs no Accessibility permission).
final class HotKey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in HotKey.action?(); return noErr },
                            1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C4953), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
