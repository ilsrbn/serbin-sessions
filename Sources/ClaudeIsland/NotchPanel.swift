import AppKit
import SwiftUI
import IslandCore

@MainActor
final class NotchUIState: ObservableObject {
    @Published var hovering = false
    @Published var pinned = false
    @Published var showingNew = false
    @Published var selectedId: String?
    @Published var expanded = false
    /// Physical notch width (0 on Macs without one) so the collapsed view can keep clear of it.
    var notchWidth: CGFloat = 0

    func recompute(hasPending: Bool) {
        expanded = hovering || pinned || showingNew || hasPending
    }
}

/// Borderless, non-activating panel pinned to the top-center of the screen (over the notch).
final class NotchPanel: NSPanel {
    static let expandedSize = NSSize(width: 700, height: 460)
    private(set) var collapsedSize = NSSize(width: 300, height: 34)
    private(set) var notchWidth: CGFloat = 0

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
        measureNotch()
        ui.notchWidth = notchWidth
        contentView = NSHostingView(rootView: NotchView(store: store, ui: ui))
    }

    override var canBecomeKey: Bool { true }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func measureNotch() {
        guard let s = targetScreen else { return }
        let inset = s.safeAreaInsets.top
        if inset > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            notchWidth = s.frame.width - l.width - r.width
            collapsedSize = NSSize(width: notchWidth + 120, height: inset)
        } else {
            notchWidth = 0
            collapsedSize = NSSize(width: 240, height: 30)
        }
    }

    /// Screen rect the panel occupies in the given state (top-center of the notch screen).
    func rect(expanded: Bool) -> NSRect? {
        guard let screen = targetScreen else { return nil }
        let size = expanded ? Self.expandedSize : collapsedSize
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    func reposition(expanded: Bool) {
        guard let r = rect(expanded: expanded), r != frame else { return }
        setFrame(r, display: true, animate: false) // animating moves the window under the cursor => hover flicker
    }
}
