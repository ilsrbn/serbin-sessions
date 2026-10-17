import AppKit
import SwiftUI
import Combine
import IslandCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let store = SessionStore()
    private let server = SocketServer()
    private var panel: NotchPanel?
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let ui = NotchUIState()
        let panel = NotchPanel(store: store, ui: ui)
        self.panel = panel
        panel.reposition(expanded: false)
        panel.orderFrontRegardless()

        // Resize panel when expansion or pending approvals change.
        Publishers.CombineLatest(ui.$hovering, store.$pending)
            .receive(on: RunLoop.main)
            .sink { [weak panel] hovering, pending in
                ui.expanded = hovering || !pending.isEmpty
                panel?.reposition(expanded: ui.expanded)
            }
            .store(in: &cancellables)

        let store = self.store
        do {
            try server.start { env, respond in
                Task { @MainActor in store.handle(env, respond: respond) }
            }
        } catch {
            NSLog("claude-island: socket start failed: \(error)")
            NSApp.terminate(nil)
        }
    }
}
