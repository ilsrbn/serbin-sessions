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
                ui.recompute(hasPending: !store.pending.isEmpty)
                panel?.reposition(expanded: ui.expanded)
                if ui.expanded && (ui.pinned || ui.showingNew) && !(panel?.isKeyWindow ?? true) { panel?.makeKey() }
            }
            .store(in: &cancellables)

        // Clicking away from the panel ends "typing" so it can collapse again.
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { _ in ui.typing = false }
            .store(in: &cancellables)

        // Global hotkey: ⌃⌥Space opens the panel with the composer focused (again: closes it).
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            MainActor.assumeIsolated { self?.perform(.toggle) }
        }

        // Sound when a new approval shows up.
        store.$pending
            .map(\.count).removeDuplicates().scan((0, 0)) { ($0.1, $1) }
            .filter { $0.1 > $0.0 }
            .sink { _ in NSSound(named: "Glass")?.play() }
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
            NSLog("claude-island: socket start failed: \(error)")
            NSApp.terminate(nil)
        }
    }

    /// Panel control shared by the global hotkey, `notch-hook <cmd>` and claude-island:// URLs.
    @MainActor
    func perform(_ cmd: IslandCommand) {
        guard let panel else { return }
        switch cmd {
        case .toggle: perform(ui.expanded ? .close : .open)
        case .open: panel.summon(ui)
        case .new:
            ui.showingNew = true
            panel.summon(ui)
        case .close:
            ui.typing = false; ui.pinned = false; ui.showingNew = false; ui.hovering = false
            hoverNeedsExit = true
            panel.resignKey()
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == IslandCommand.urlScheme {
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
            // Stay open while the cursor is anywhere over the expanded panel (plus a margin).
            let keep = panel.rect(expanded: true)?.insetBy(dx: -12, dy: -12)
            if keep?.contains(m) == true { outsideSince = nil; return }
            let since = outsideSince ?? now
            outsideSince = since
            if now.timeIntervalSince(since) > 0.4 { ui.hovering = false; outsideSince = nil }
        } else {
            // Open after a short dwell on the collapsed notch area.
            let trigger = panel.rect(expanded: false)?.insetBy(dx: -6, dy: -4).offsetBy(dx: 0, dy: -2)
            let inside = trigger.map { $0.contains(m) || m.y >= $0.maxY - 1 && abs(m.x - $0.midX) < $0.width / 2 } ?? false
            if hoverNeedsExit {
                if !inside { hoverNeedsExit = false }
                return
            }
            if inside {
                let since = insideSince ?? now
                insideSince = since
                if now.timeIntervalSince(since) > 0.12 { ui.hovering = true; insideSince = nil }
            } else { insideSince = nil }
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
