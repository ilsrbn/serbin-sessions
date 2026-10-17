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
    func applicationWillTerminate(_ notification: Notification) {
        store.stopAllManaged()
    }
}
