import SwiftUI
import AppKit
import IslandCore

struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState
    let session: Session

    private var items: [TranscriptItem] { store.transcripts[session.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.primary.opacity(0.12))
            transcript
        }
    }

    /// Starts at, and follows, the newest message. Not lazy: heights must be known for the bottom
    /// anchor to be exact. `.id(session.id)` gives each session a fresh scroll view that opens at the end.
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { ItemRow(item: $0).id($0.id) }
                    Color.clear.frame(height: 1).id(Self.bottomId)
                }.padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: items.last?.id) { old, new in
                guard new != nil else { return }
                if old == nil { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
        }
        .id(session.id)
    }

    private static let bottomId = "bottom"

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.headline)
                Text(session.cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(session.state.label).font(.caption).foregroundStyle(session.state.color).lineLimit(2).frame(maxWidth: 220, alignment: .trailing)
            if case .needsInput = session.state {
                Button("Dismiss") { store.dismiss(session.id) }.help("Clear this flag (answered in the terminal)")
            }
            if session.isManaged {
                Button("Stop") { store.stop(session.id) }
            } else if session.state == .done || session.state.isFailed {
                Button("Resume here") {
                    store.startManaged(cwd: session.cwd, prompt: "continue", mode: .default, resume: session.id)
                }.help("Continue this session from the panel")
            }
            Button("Terminal") { openTerminal(session.cwd) }
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func openTerminal(_ cwd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", cwd]
        try? p.run()
    }
}

extension SessionState {
    var isFailed: Bool { if case .failed = self { return true }; return false }
}

struct ItemRow: View {
    let item: TranscriptItem

    var body: some View {
        switch item.kind {
        case .user:
            Text(item.text).font(.callout)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        case .assistant:
            Text(markdown(item.text)).font(.callout).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let name):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench.and.screwdriver").font(.caption2)
                Text(name).font(.caption.bold())
                Text(item.text).font(.system(.caption, design: .monospaced)).lineLimit(2)
            }.foregroundStyle(.secondary)
        case .toolResult:
            Text(item.text).font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary).lineLimit(2).padding(.leading, 18)
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

struct NewSessionView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState

    @StateObject private var form = NewSessionForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New session").font(.headline)
            HStack {
                TextField("Folder", text: $form.cwd).textFieldStyle(.roundedBorder)
                Button("Choose…", action: chooseFolder)
            }
            TextEditor(text: $form.prompt)
                .font(.callout).frame(height: 90)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Picker("Mode", selection: $form.mode) {
                    Text("Ask").tag(PermissionMode.default)
                    Text("Accept edits").tag(PermissionMode.acceptEdits)
                    Text("Plan").tag(PermissionMode.plan)
                }.pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Button("Start") {
                    store.startManaged(cwd: form.cwd, prompt: form.prompt, mode: form.mode)
                    form.prompt = ""
                    ui.showingNew = false
                    ui.selectedId = store.ordered.first(where: { $0.isManaged })?.id
                }
                .islandButton(prominent: true)
                .disabled(form.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !FileManager.default.fileExists(atPath: form.cwd))
            }
            Divider().overlay(Color.primary.opacity(0.12))
            Text("Recent").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(form.recent) { r in
                        Button {
                            form.cwd = r.cwd
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.caption.bold())
                                Text(r.firstPrompt).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Resume this session") {
                                store.startManaged(cwd: r.cwd, prompt: "continue", mode: form.mode, resume: r.id)
                                ui.showingNew = false
                                ui.selectedId = r.id
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .onAppear { form.recent = RecentSessions.scan() }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { form.cwd = u.path }
    }
}

// @State needs the SwiftUIMacros plugin (full Xcode); plain ObservableObjects build everywhere.
final class NewSessionForm: ObservableObject {
    @Published var cwd = NSHomeDirectory() + "/Dev"
    @Published var prompt = ""
    @Published var mode: PermissionMode = .default
    @Published var recent: [RecentSession] = []
}

/// Always-visible message box. Sends to the selected session; a finished terminal session is
/// resumed as a managed one. Active terminal sessions can't be written to, so it is disabled.
struct Composer: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState
    let session: Session?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        guard let s = session else { return false }
        if s.isManaged { return true }
        switch s.state {
        case .done, .failed, .idle: return true
        default: return false
        }
    }

    private var placeholder: String {
        guard let s = session else { return "Start a session with “New session”" }
        if canSend { return s.isManaged ? "Message \(s.title)…  (↵ send, esc close)" : "Resume \(s.title) with a message…" }
        return "Terminal session is active — reply in the terminal"
    }

    var body: some View {
        HStack {
            TextField(placeholder, text: $ui.draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(!canSend)
                .onSubmit(send)
                .onExitCommand { ui.closeRequest += 1 }
            Button("Send", action: send).islandButton(prominent: true)
                .disabled(!canSend || ui.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onChange(of: focused) { _, f in ui.typing = f }
        .onChange(of: ui.focusTick) { _, _ in focused = true }
    }

    private func send() {
        let t = ui.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let s = session, canSend else { return }
        if s.isManaged { store.send(t, to: s.id) }
        else { store.startManaged(cwd: s.cwd, prompt: t, mode: .default, resume: s.id) }
        ui.draft = ""
    }
}
