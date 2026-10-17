import SwiftUI
import IslandCore

extension SessionState {
    var color: Color {
        switch self {
        case .idle: .gray
        case .running: .blue
        case .needsApproval: .orange
        case .needsInput: .purple
        case .done: .green
        case .failed: .red
        }
    }

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

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState

    var body: some View {
        ZStack(alignment: .top) {
            if ui.expanded {
                // Glass all the way up; the hardware notch simply covers its own middle part.
                Rectangle().fill(.clear)
                    .islandGlass(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
                ExpandedView(store: store, ui: ui)
            } else {
                Rectangle().fill(.clear)
                    .islandGlass(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                collapsed
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: ui.expanded ? 28 : 18,
                                          bottomTrailingRadius: ui.expanded ? 28 : 18))
        .animation(.smooth(duration: 0.25), value: ui.expanded)
    }

    private var top: Session? { store.ordered.first }

    private var summaryColor: Color {
        if !store.pending.isEmpty { return .orange }
        return top?.state.color ?? .gray
    }

    private var summaryText: String {
        if let p = store.pending.first { return p.toolName }
        guard let t = top else { return "" }
        if case .running(let tool) = t.state { return tool ?? t.title }
        return t.title
    }

    /// Left ear: status dot + count of sessions that need you. Right ear: what the top session is doing.
    private var collapsed: some View {
        // Three fixed zones centered on the screen: [left ear][notch gap][right ear]. The gap is the
        // reported notch width plus its rounded shoulders, so nothing can slide under the hardware.
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(summaryColor).frame(width: 9, height: 9)
                    .opacity(store.sessions.isEmpty ? 0.4 : 1)
                let urgent = store.sessions.values.filter { $0.state.urgency >= 4 }.count
                if urgent > 0 {
                    Text("\(urgent)").font(.caption.bold().monospacedDigit()).foregroundStyle(summaryColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)

            Color.clear.frame(width: NotchPanel.notchGap(ui.notchWidth))

            Text(summaryText)
                .font(.caption).foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 14)
        }
        .frame(maxHeight: .infinity)
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
            .padding(8).background(Color.yellow.opacity(0.15))
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

struct ApprovalCard: View {
    let store: SessionStore
    let approval: PendingApproval

    private var managed: Bool { store.sessions[approval.sessionId]?.isManaged == true }
    private var title: String { store.sessions[approval.sessionId]?.title ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(approval.toolName).font(.callout.bold()).foregroundStyle(.orange)
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
                        .keyboardShortcut("y", modifiers: .command).tint(.green).islandButton(prominent: true)
                    if !managed { // -p sessions have no terminal dialog to fall back to
                        Button("Ask in terminal") { store.resolve(approval, .ask) }
                    }
                }
            }
        }
        .padding(10)
        .islandGlass(RoundedRectangle(cornerRadius: 16), tint: .orange.opacity(0.28))
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
