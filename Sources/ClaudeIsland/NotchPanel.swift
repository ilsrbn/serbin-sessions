import AppKit
import SwiftUI
import IslandCore

@MainActor
final class NotchUIState: ObservableObject {
    @Published var hovering = false
    @Published var expanded = false
}

/// Borderless, non-activating panel pinned to the top-center of the screen (over the notch).
final class NotchPanel: NSPanel {
    private static let collapsedSize = NSSize(width: 260, height: 34)
    private static let expandedSize = NSSize(width: 520, height: 320)

    @MainActor
    init(store: SessionStore, ui: NotchUIState) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: NotchView(store: store, ui: ui))
    }

    override var canBecomeKey: Bool { true }

    func reposition(expanded: Bool) {
        guard let screen = NSScreen.main else { return }
        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let f = screen.frame
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }
}
