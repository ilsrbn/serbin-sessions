import AppKit
import SwiftUI
import Combine
import IslandCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let store = SessionStore()
    @MainActor private let ui = NotchUIState()
    private let server = SocketServer()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var insideSince: Date?
    private var outsideSince: Date?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = self.store, ui = self.ui
        let panel = NotchPanel(store: store, ui: ui)
        self.panel = panel
        panel.reposition(expanded: false)
        panel.orderFrontRegardless()

        // Resize the panel when expansion state changes.
        Publishers.CombineLatest4(ui.$hovering, ui.$pinned, ui.$showingNew, store.$pending)
            .receive(on: RunLoop.main)
            .sink { [weak panel] hovering, pinned, showingNew, pending in
                ui.recompute(hasPending: !pending.isEmpty)
                panel?.reposition(expanded: ui.expanded)
                if ui.expanded && (pinned || showingNew) { panel?.makeKey() }
            }
            .store(in: &cancellables)

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
            try server.start { env, channel in
                Task { @MainActor in store.handle(env, channel: channel) }
            }
        } catch {
            NSLog("claude-island: socket start failed: \(error)")
            NSApp.terminate(nil)
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
