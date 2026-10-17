import SwiftUI
import AppKit
import IslandCore

struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState
    let session: Session

    @StateObject private var form = DetailForm()
    @FocusState private var focused: Bool

    private var items: [TranscriptItem] { store.transcripts[session.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { ItemRow(item: $0).id($0.id) }
                    }.padding(12)
                }
                .onChange(of: items.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .onAppear { if let id = items.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if session.isManaged { inputBar }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.headline)
                Text(session.cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(session.state.label).font(.caption).foregroundStyle(session.state.color).lineLimit(1)
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

    private var inputBar: some View {
        HStack {
            TextField("Message Claude…", text: $form.draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(send)
                .onChange(of: focused) { _, f in if f { ui.pinned = true } }
            Button("Send", action: send).disabled(form.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private func send() {
        let t = form.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.send(t, to: session.id)
        form.draft = ""
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
                .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
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
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                .buttonStyle(.borderedProminent)
                .disabled(form.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || !FileManager.default.fileExists(atPath: form.cwd))
            }
            Divider().overlay(Color.white.opacity(0.1))
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
final class DetailForm: ObservableObject {
    @Published var draft = ""
}

final class NewSessionForm: ObservableObject {
    @Published var cwd = NSHomeDirectory() + "/Dev"
    @Published var prompt = ""
    @Published var mode: PermissionMode = .default
    @Published var recent: [RecentSession] = []
}
