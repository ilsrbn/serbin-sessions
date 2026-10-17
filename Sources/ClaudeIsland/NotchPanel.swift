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
    /// Titles of sessions that just finished; shown briefly in the collapsed pill, then cleared.
    @Published var doneFlash: [String] = []
    private var flashClear: Task<Void, Never>?
    /// Sound is opt-in, and only ever plays for requests that need the user.
    @Published var soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled") {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    /// Physical notch width (0 on Macs without one) so the collapsed view can keep clear of it.
    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 32
    /// Pill width with the ears out (signal / peek) and at rest (just the notch plus its shoulders).
    var collapsedWidth: CGFloat = 300
    var baseWidth: CGFloat = 110
    /// While a signal is on, the pill drops this far below the notch so its whole lower edge is visible.
    static let signalExtra: CGFloat = 3
    /// Start of the current "done" sweep / "needs you" sweep, for the edge light.
    var doneStart = Date.distantPast
    var urgentStart = Date.distantPast
    /// Cursor is resting on the notch: the ears slide out with a hint, before the full panel opens.
    @Published var peeking = false
    /// Last ear text shown, so the ears keep their content while they retract.
    let earCache = EarCache()

    /// Several finishes inside the window collapse into one "N sessions" signal.
    func flashDone(_ title: String) {
        if doneFlash.isEmpty || Date().timeIntervalSince(doneStart) > 1.8 { doneStart = Date() }
        if !doneFlash.contains(title) { doneFlash.append(title) }
        flashClear?.cancel()
        flashClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.doneFlash = []
        }
    }

    /// Never opens by itself: only hover, pin, the new-session form or typing expand the panel.
    func recompute() {
        let v = hovering || pinned || showingNew || typing
        if v != expanded { expanded = v }
    }
}

final class EarCache { var left = ""; var right = ""; var amber = false }

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
        ui.collapsedWidth = collapsedSize.width
        ui.baseWidth = notchWidth > 0 ? Self.notchGap(notchWidth) : 110
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
            collapsedSize = NSSize(width: Self.notchGap(notchWidth) + 2 * Self.earWidth, height: inset)
        } else {
            notchWidth = 0
            collapsedSize = NSSize(width: 240, height: 30)
        }
    }

    /// Horizontal room for the status text on each side of the notch in the collapsed pill.
    static let earWidth: CGFloat = 112

    /// Dead zone in the middle of the collapsed pill: the reported notch width plus its rounded
    /// shoulders (the hardware cutout is visibly wider than `auxiliaryTop*Area` suggests).
    static func notchGap(_ notchWidth: CGFloat) -> CGFloat { notchWidth + 24 }

    /// Hover target for the collapsed pill: just the notch at rest, the whole pill while its ears are out.
    func collapsedRect(wide: Bool, baseWidth: CGFloat) -> NSRect? {
        guard var r = rect(expanded: false) else { return nil }
        if !wide { r = NSRect(x: r.midX - baseWidth / 2, y: r.minY, width: baseWidth, height: r.height) }
        return r
    }

    /// Screen rect the panel occupies in the given state (top-center of the notch screen).
    func rect(expanded: Bool) -> NSRect? {
        guard let screen = targetScreen else { return nil }
        let size = expanded ? Self.expandedSize : collapsedSize
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    /// The window is always full size and transparent; SwiftUI animates the black shape inside it, so
    /// the pill grows smoothly instead of the window frame and the layout fighting each other.
    /// While collapsed the empty window must not swallow clicks meant for the apps underneath.
    func reposition(expanded: Bool) {
        if let r = rect(expanded: true), r != frame { setFrame(r, display: true) }
        ignoresMouseEvents = !expanded
    }
}
