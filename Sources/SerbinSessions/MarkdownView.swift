import SwiftUI
import AppKit
import IslandCore

/// Assistant text with its block structure: headings, lists, tables, code, quotes, images.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    init(_ text: String) { blocks = MarkdownCache.blocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in block(b) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ b: MarkdownBlock) -> some View {
        switch b {
        case .heading(let level, let text):
            inline(text).font(headingFont(level)).fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            inline(text).font(.callout)
        case .code(_, let text):
            Text(text).font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 2)
                inline(text).font(.callout).foregroundStyle(.secondary)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(it.marker).font(.callout).foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        inline(it.text).font(.callout)
                    }.padding(.leading, CGFloat(it.depth) * 16)
                }
            }
        case .table(let header, let aligns, let rows):
            table(header, aligns, rows)
        case .image(let alt, let url):
            MarkdownImage(alt: alt, url: url)
        case .rule:
            Divider().overlay(Theme.hairline)
        }
    }

    private func table(_ header: [String], _ aligns: [MarkdownBlock.Align], _ rows: [[String]]) -> some View {
        // No horizontal ScrollView: nested in the transcript's scroll view it collapsed to nothing.
        // Long cells wrap instead.
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { c, h in
                        cell(h, aligns[c], bold: true)
                    }
                }
                .background(Color.white.opacity(0.08))
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { c, text in
                            cell(text, aligns[c], bold: false)
                        }
                    }
                    .background(r % 2 == 1 ? Color.white.opacity(0.03) : Color.clear)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func cell(_ text: String, _ a: MarkdownBlock.Align, bold: Bool) -> some View {
        inline(text).font(.caption).fontWeight(bold ? .semibold : .regular)
            .multilineTextAlignment(a == .center ? .center : a == .trailing ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: a == .center ? .center : a == .trailing ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3
        case 2: .headline
        default: .callout
        }
    }

    private func inline(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
             ?? AttributedString(s))
    }
}

/// Parsing runs on every row render; the transcript re-renders often, so keep the results.
@MainActor
enum MarkdownCache {
    private static var cache: [String: [MarkdownBlock]] = [:]

    static func blocks(_ text: String) -> [MarkdownBlock] {
        if let b = cache[text] { return b }
        if cache.count > 400 { cache.removeAll() }
        let b = MarkdownParser.parse(text)
        cache[text] = b
        return b
    }
}

/// Remote images load asynchronously; local paths (absolute, ~/ or file://) are read from disk.
struct MarkdownImage: View {
    let alt: String
    let url: String

    var body: some View {
        Group {
            if let local = localImage() {
                Image(nsImage: local).resizable().scaledToFit()
            } else if let u = URL(string: url), u.scheme == "http" || u.scheme == "https" {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: placeholder("photo.badge.exclamationmark")
                    default: ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
            } else {
                placeholder("photo")
            }
        }
        .frame(maxWidth: 420, maxHeight: 280, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(alt)
    }

    private func localImage() -> NSImage? {
        var path = url
        if path.hasPrefix("file://") { path = URL(string: path)?.path ?? String(path.dropFirst(7)) }
        else if path.hasPrefix("~/") { path = NSString(string: path).expandingTildeInPath }
        guard path.hasPrefix("/") else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func placeholder(_ symbol: String) -> some View {
        Label(alt.isEmpty ? url : alt, systemImage: symbol)
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
    }
}
