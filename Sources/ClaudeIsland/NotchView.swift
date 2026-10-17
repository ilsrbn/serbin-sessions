import SwiftUI
import IslandCore

extension SessionState {
    var color: Color {
        switch self {
        case .idle: Color(white: 0.4)
        case .running: Color(white: 0.8)
        case .needsApproval, .needsInput: Theme.amber
        case .done: Color(white: 0.55)
        case .failed: Color(red: 1, green: 0.4, blue: 0.4)
        }
    }

    /// One or two words for the peek ear.
    var brief: String {
        switch self {
        case .idle: "Idle"
        case .running(let tool): tool ?? "Working…"
        case .needsApproval: "Needs approval"
        case .needsInput: "Asks"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    var isRunning: Bool { if case .running = self { true } else { false } }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .running(let tool): tool.map { "Running \($0)" } ?? "Working…"
        case .needsApproval: "Waiting for approval"
        case .needsInput(let m): "Asks: \(m)"
        case .done: "Done"
        case .failed(let m): "Failed: \(m)"
        }
    }
}

extension SessionStore {
    /// Sessions waiting on the user (approval or question).
    var urgentCount: Int {
        max(pending.count, sessions.values.filter { $0.state.urgency >= 4 }.count)
    }
}

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState

    var body: some View {
        let r: CGFloat = ui.expanded ? 28 : 18
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
        let size = ui.expanded ? NotchPanel.expandedSize
            : NSSize(width: wide ? ui.collapsedWidth : ui.baseWidth,
                     height: ui.notchHeight + (signal ? NotchUIState.signalExtra : 0))
        ZStack(alignment: .top) {
            shape.fill(Theme.bg)
            if ui.expanded {
                // Laid out at its final size from the first frame; the growing shape just reveals it.
                ExpandedView(store: store, ui: ui)
                    .frame(width: NotchPanel.expandedSize.width, height: NotchPanel.expandedSize.height)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                                            removal: .opacity.animation(.easeIn(duration: 0.08))))
            } else {
                collapsed
                    .frame(width: ui.collapsedWidth, height: ui.notchHeight)
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
                                            removal: .opacity.animation(.easeIn(duration: 0.08))))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay { if ui.expanded { shape.stroke(Theme.hairline, lineWidth: 1) } }
        .overlay {
            if !ui.expanded && signal { EdgeLight(ui: ui, urgent: urgent > 0).transition(.opacity) }
        }
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .animation(.spring(duration: 0.42, bounce: 0.1), value: ui.expanded)
        .animation(.spring(duration: 0.38, bounce: 0.08), value: wide)
        .animation(.spring(duration: 0.38, bounce: 0.08), value: signal)
    }

    /// Something to show on the edge: needs you (amber, stays) or just finished (white, one sweep).
    private var signal: Bool { urgent > 0 || !ui.doneFlash.isEmpty }

    /// Ears out: something needs you or the cursor is resting on the notch. A finish is edge light only.
    private var wide: Bool { ui.peeking || urgent > 0 }

    private var top: Session? { store.ordered.first }

    private var urgent: Int { store.urgentCount }

    private var summaryText: String {
        if let p = store.pending.first { return p.toolName }
        guard let t = top else { return "" }
        if case .running(let tool) = t.state { return tool ?? t.title }
        return t.title
    }

    /// Text for the two ears. Quiet by default: nothing at rest, a persistent amber signal when
    /// something needs you, "Done" for a hint while the cursor rests.
    private var earContent: (left: String, right: String, amber: Bool) {
        if urgent > 0 { return ("\(urgent)", summaryText, true) }
        if ui.peeking {
            guard let t = top else { return ("No sessions", "", false) }
            return (t.title, t.state.brief, false)
        }
        return ("", "", false)
    }

    private var collapsed: some View {
        // Three fixed zones centered on the screen: [left ear][notch gap][right ear]. The gap is the
        // reported notch width plus its rounded shoulders, so nothing can slide under the hardware.
        // The pill itself is narrower at rest; this layout stays full width and is revealed as it grows.
        // While the ears retract they keep their last text instead of flashing the new (empty) one.
        let cache = ui.earCache
        if wide { let c = earContent; cache.left = c.left; cache.right = c.right; cache.amber = c.amber }
        return HStack(spacing: 0) {
            Text(cache.left)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(cache.amber ? Theme.amber : Color.primary.opacity(0.9))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 14).padding(.trailing, 6)

            Color.clear.frame(width: NotchPanel.notchGap(ui.notchWidth))

            Text(cache.right)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6).padding(.trailing, 14)
        }
        .frame(maxHeight: .infinity)
        .opacity(wide ? 1 : 0)
        .animation(wide ? .easeOut(duration: 0.2).delay(0.12) : .easeIn(duration: 0.08), value: wide)
    }
}

/// Open outline of the pill: down the left side, along the bottom, up the right side. No top edge,
/// since the top sits against the screen edge.
struct EdgeLine: Shape {
    var radius: CGFloat = 18

    func path(in r: CGRect) -> Path {
        let l = r.minX + 1, rt = r.maxX - 1, b = r.maxY - 1
        var p = Path()
        p.move(to: CGPoint(x: l, y: r.minY))
        p.addLine(to: CGPoint(x: l, y: b - radius))
        p.addArc(tangent1End: CGPoint(x: l, y: b), tangent2End: CGPoint(x: l + radius, y: b), radius: radius)
        p.addLine(to: CGPoint(x: rt - radius, y: b))
        p.addArc(tangent1End: CGPoint(x: rt, y: b), tangent2End: CGPoint(x: rt, y: b - radius), radius: radius)
        p.addLine(to: CGPoint(x: rt, y: r.minY))
        return p
    }
}

/// The one signal language: light running along the pill's edge. Amber = needs you (sweeps in from
/// the bottom center, then breathes until answered). White = finished (a single sweep that fades).
struct EdgeLight: View {
    @ObservedObject var ui: NotchUIState
    let urgent: Bool

    var body: some View {
        TimelineView(.animation) { ctx in
            let (p, o) = phase(ctx.date)
            let color = urgent ? Theme.amber : Color.white.opacity(0.92)
            ZStack {
                EdgeLine().trim(from: 0.5 - p / 2, to: 0.5 + p / 2)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).blur(radius: 3).opacity(0.75 * o)
                EdgeLine().trim(from: 0.5 - p / 2, to: 0.5 + p / 2)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).opacity(o)
            }
        }
        .allowsHitTesting(false)
    }

    /// (fraction of the outline drawn, opacity)
    private func phase(_ now: Date) -> (CGFloat, Double) {
        func ease(_ x: Double) -> CGFloat { CGFloat(1 - pow(1 - min(max(x, 0), 1), 3)) }
        if urgent {
            let e = now.timeIntervalSince(ui.urgentStart)
            return (ease(e / 0.7), 0.7 + 0.3 * sin(now.timeIntervalSinceReferenceDate * 2.4))
        }
        let e = now.timeIntervalSince(ui.doneStart)
        return (ease(e / 0.7), e < 1.6 ? 1 : max(0, 1 - (e - 1.6) / 0.9))
    }
}

struct ExpandedView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState

    private var selected: Session? {
        if let id = ui.selectedId, let s = store.sessions[id] { return s }
        return store.ordered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: ui.notchHeight + 4) // keep clear of the physical notch
            if let hint = hookHint { hint }
            if !store.pending.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.pending) { ApprovalCard(store: store, approval: $0) }
                    }.padding(.horizontal, 14).padding(.bottom, 6)
                }.frame(maxHeight: 190)
            }
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Divider().overlay(Color.primary.opacity(0.12))
                Group {
                    if ui.showingNew { NewSessionView(store: store, ui: ui) }
                    else if let s = selected { SessionDetailView(store: store, ui: ui, session: s) }
                    else { Text("No Claude Code sessions").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
            if !ui.showingNew { Composer(store: store, ui: ui, session: selected) }
            footer
        }
    }

    private var hookHint: AnyView? {
        guard !HooksInstaller.isInstalled() else { return nil }
        return AnyView(
            HStack {
                Text("Hooks not installed — sessions won't show up.").font(.caption)
                Spacer()
                Button("Install hooks") {
                    if let bin = HooksInstaller.defaultHookBinary() {
                        try? HooksInstaller.install(hookBinary: bin)
                    }
                    ui.objectWillChange.send()
                }.controlSize(.small)
            }
            .padding(8).background(Theme.amber.opacity(0.15))
        )
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.ordered) { s in
                    Button { ui.selectedId = s.id; ui.showingNew = false } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(s.state.color).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).font(.callout.bold()).lineLimit(1)
                                Text(s.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if s.isManaged { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .padding(6)
                        .background(selected?.id == s.id && !ui.showingNew ? Color.primary.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(8)
        }
    }

    private var footer: some View {
        HStack {
            Button { ui.showingNew.toggle() } label: { Label("New session", systemImage: "plus") }
            Spacer()
            if let e = store.lastError { Text(e).font(.caption).foregroundStyle(.red).lineLimit(1) }
            Button { ui.soundEnabled.toggle() } label: { Image(systemName: ui.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash") }
                .help(ui.soundEnabled ? "Sound on for requests that need you" : "Sound off")
            Text("⌃⌥Space").font(.caption2).foregroundStyle(.tertiary).help("Global hotkey: open and type")
            Button { ui.pinned.toggle() } label: { Image(systemName: ui.pinned ? "pin.fill" : "pin") }
                .help("Keep open")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
    }
}

extension ApprovalCard {
    /// "Always allow" mirrors the don't-ask-again options of Claude Code's own dialog.
    @ViewBuilder var alwaysAllow: some View {
        if approval.suggestions.count == 1, let one = approval.suggestions.first {
            Button("Always allow") { store.resolve(approval, .allow, remember: one) }
                .help(one.label).islandButton()
        } else if approval.suggestions.count > 1 {
            Menu("Always allow") {
                ForEach(approval.suggestions) { sug in
                    Button(sug.label) { store.resolve(approval, .allow, remember: sug) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}

struct ApprovalCard: View {
    let store: SessionStore
    let approval: PendingApproval

    private var managed: Bool { store.sessions[approval.sessionId]?.isManaged == true }
    private var title: String { store.sessions[approval.sessionId]?.title ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(approval.toolName).font(.callout.bold()).foregroundStyle(Theme.amber)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(approval.summary)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(6).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                if approval.terminalOnly {
                    Text("Needs an answer in the terminal").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { store.resolve(approval, .ask) }
                } else {
                    Button("Deny") { store.resolve(approval, .deny, message: "Denied from Claude Island") }
                        .keyboardShortcut("n", modifiers: .command).islandButton()
                    Button("Allow") { store.resolve(approval, .allow) }
                        .keyboardShortcut("y", modifiers: .command).islandButton(prominent: true)
                    alwaysAllow
                    if !managed { // -p sessions have no terminal dialog to fall back to
                        Button("Ask in terminal") { store.resolve(approval, .ask) }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.amber.opacity(0.4), lineWidth: 1))
    }
}

extension Session {
    /// Live sessions show their state; finished/historical ones show what they were about and when.
    var subtitle: String {
        guard state == .done || state == .idle else { return state.label }
        let ago = RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: Date())
        let what = (lastPrompt ?? "").replacingOccurrences(of: "\n", with: " ")
        return what.isEmpty ? ago : "\(ago) · \(what)"
    }
}
