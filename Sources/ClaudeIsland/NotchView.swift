import SwiftUI
import IslandCore

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var ui: NotchUIState

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                .fill(.black)
            if ui.expanded { expanded } else { collapsed }
        }
        .onHover { ui.hovering = $0 }
        .preferredColorScheme(.dark)
    }

    private var summaryColor: Color {
        if !store.pending.isEmpty { return .orange }
        if store.sessions.values.contains(where: { if case .running = $0.state { return true }; return false }) { return .blue }
        if store.sessions.values.contains(where: { $0.state == .done }) { return .green }
        return .gray
    }

    private var collapsed: some View {
        HStack {
            Circle().fill(summaryColor).frame(width: 10, height: 10)
            Spacer()
            if !store.sessions.isEmpty {
                Text("\(store.sessions.count)").font(.caption.monospacedDigit()).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    private var expanded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.pending) { ApprovalCard(store: store, approval: $0) }
                ForEach(store.ordered) { SessionRow(session: $0) }
                if store.sessions.isEmpty {
                    Text("No Claude Code sessions").foregroundStyle(.secondary).font(.callout)
                }
            }
            .padding(.top, 38)
            .padding(16)
        }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.callout.bold())
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
    }

    private var color: Color {
        switch session.state {
        case .idle: .gray
        case .running: .blue
        case .needsApproval: .orange
        case .done: .green
        }
    }

    private var status: String {
        switch session.state {
        case .idle: session.lastPrompt ?? "Idle"
        case .running(let tool): tool.map { "Running \($0)" } ?? "Working…"
        case .needsApproval: "Waiting for approval"
        case .done: session.lastMessage ?? "Done"
        }
    }
}

struct ApprovalCard: View {
    let store: SessionStore
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.toolName).font(.callout.bold()).foregroundStyle(.orange)
            Text(approval.summary)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Deny") { store.resolve(approval, .deny, message: "Denied from Claude Island") }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Allow") { store.resolve(approval, .allow) }
                    .keyboardShortcut("y", modifiers: .command)
                Button("Ask in terminal") { store.resolve(approval, .ask) }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
