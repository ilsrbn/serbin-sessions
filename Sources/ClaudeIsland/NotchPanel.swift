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
    /// Composer has keyboard focus (or was summoned by the hotkey). Cleared when the panel loses key status.
    @Published var typing = false
    @Published var draft = ""
    @Published var focusTick = 0
    /// Bumped by views (Esc in the composer) to ask the app to close the panel.
    @Published var closeRequest = 0
    /// Physical notch width (0 on Macs without one) so the collapsed view can keep clear of it.
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 32

    func recompute(hasPending: Bool) {
        let v = hovering || pinned || showingNew || typing || hasPending
        if v != expanded { expanded = v }
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
        // The init flag alone doesn't always set the window-server "prevents activation" tag.
        styleMask.insert(.nonactivatingPanel)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true // clicking Allow/Deny must not steal key status; text fields still can
        hidesOnDeactivate = false
        level = .statusBar + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        measureNotch()
        ui.notchWidth = notchWidth
        ui.notchHeight = collapsedSize.height
        contentView = NSHostingView(rootView: NotchView(store: store, ui: ui))
        trackPreviousApp()
    }

    override var canBecomeKey: Bool { true }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() } // Esc anywhere in the panel

    /// When the panel was last summoned. Focus-loss events right after that are the launcher
    /// (Raycast) closing and handing focus back to the previous app, not the user clicking away.
    private(set) var summonedAt = Date.distantPast
    var inSummonGrace: Bool { Date().timeIntervalSince(summonedAt) < 0.6 }

    /// Open and take keyboard focus. The launcher that triggered us is still dismissing itself and
    /// re-activates the previous app a moment later, so re-assert focus a couple of times.
    @MainActor func summon(_ ui: NotchUIState) {
        summonedAt = Date()
        ui.typing = true
        ui.focusTick += 1
        takeFocus()
        for delay in [0.12, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak ui] in
                guard let self, let ui, ui.typing, !self.isKeyWindow else { return }
                self.takeFocus()
            }
        }
    }

    /// Key window WITHOUT activating the app (nonactivating panel): whatever app is in front,
    /// e.g. a fullscreen video, stays the active app and keeps its own window state.
    private func takeFocus() {
        // A claude-island:// URL makes LaunchServices activate us. Give activation straight back so
        // the user's app (and its fullscreen Space) stays active; we only keep key-window status.
        if frontIsUs, let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        orderFrontRegardless()
        makeKey()
    }

    private var frontIsUs: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Last app that was active before us. Tracked continuously because a `claude-island://` URL
    /// opened from Raycast makes LaunchServices activate us *before* our handler runs.
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    func trackPreviousApp() {
        let me = ProcessInfo.processInfo.processIdentifier
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == me ? nil : $0 }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != me else { return }
            self?.previousApp = app
        }
    }

    /// Hand keystrokes back to whatever was underneath.
    /// - Summoned without activation (hotkey / CLI): we were only the key window, so ordering out
    ///   makes the still-active app underneath key again. Nothing else is touched.
    /// - Activated by LaunchServices (URL): give activation back to the previous app explicitly.
    @MainActor func releaseFocus() {
        if frontIsUs, let app = previousApp, !app.isTerminated {
            NSApp.yieldActivation(to: app) // macOS 14+ cooperative activation
            app.activate()
        }
        if isKeyWindow {
            orderOut(nil)
            orderFrontRegardless()
        }
    }

    var holdsFocus: Bool { isKeyWindow }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func measureNotch() {
        guard let s = targetScreen else { return }
        let inset = s.safeAreaInsets.top
        if inset > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            notchWidth = s.frame.width - l.width - r.width
            collapsedSize = NSSize(width: notchWidth + 150, height: inset)
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
        setFrame(r, display: true, animate: true) // hover is polled from the mouse position, so animating is safe
    }
}
