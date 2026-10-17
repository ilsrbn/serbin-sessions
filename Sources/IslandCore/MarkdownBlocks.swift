import Foundation

public enum MarkdownBlock: Equatable, Sendable {
    public enum Align: Equatable, Sendable { case leading, center, trailing }
    public struct ListItem: Equatable, Sendable {
        public let depth: Int
        /// "•" for bullets, "1." for ordered.
        public let marker: String
        public let text: String
    }
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, text: String)
    case quote(String)
    case list([ListItem])
    case table(header: [String], aligns: [Align], rows: [[String]])
    case image(alt: String, url: String)
    case rule
}

/// Block-level Markdown parser for transcript text. Inline syntax (bold, links, `code`) is left in
/// the strings for the renderer; this only finds the blocks SwiftUI's inline parser cannot show.
public enum MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        var i = 0

        func flushPara() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.isEmpty { flushPara(); i += 1; continue }

            // Fenced code (``` or ~~~). An unterminated fence runs to the end, like while streaming.
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flushPara()
                let fence = String(t.prefix(3))
                let lang = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i]); i += 1
                }
                i += 1
                blocks.append(.code(language: lang, text: body.joined(separator: "\n")))
                continue
            }

            if let h = heading(t) { flushPara(); blocks.append(h); i += 1; continue }

            if isRule(t) { flushPara(); blocks.append(.rule); i += 1; continue }

            if let img = image(t) { flushPara(); blocks.append(img); i += 1; continue }

            if t.hasPrefix(">") {
                flushPara()
                var q: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    q.append(String(l.dropFirst()).trimmingCharacters(in: .init(charactersIn: " ")))
                    i += 1
                }
                blocks.append(.quote(q.joined(separator: "\n")))
                continue
            }

            // Table: a row with pipes followed by a separator row (---|:---:).
            if t.contains("|"), i + 1 < lines.count, let aligns = separator(lines[i + 1]) {
                let header = cells(t)
                if header.count == aligns.count {
                    flushPara()
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count {
                        let l = lines[i].trimmingCharacters(in: .whitespaces)
                        guard !l.isEmpty, l.contains("|") else { break }
                        var r = cells(l)
                        while r.count < header.count { r.append("") }
                        rows.append(Array(r.prefix(header.count)))
                        i += 1
                    }
                    blocks.append(.table(header: header, aligns: aligns, rows: rows))
                    continue
                }
            }

            if listItem(line) != nil {
                flushPara()
                var items: [MarkdownBlock.ListItem] = []
                while i < lines.count {
                    if let it = listItem(lines[i]) { items.append(it); i += 1 }
                    // Indented continuation of the previous item.
                    else if !items.isEmpty, lines[i].hasPrefix("  "),
                            !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        let last = items.removeLast()
                        items.append(.init(depth: last.depth, marker: last.marker,
                                           text: last.text + "\n" + lines[i].trimmingCharacters(in: .whitespaces)))
                        i += 1
                    } else { break }
                }
                blocks.append(.list(items))
                continue
            }

            para.append(line)
            i += 1
        }
        flushPara()
        return blocks
    }

    static func heading(_ t: String) -> MarkdownBlock? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        var text = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(level: hashes, text: text.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ t: String) -> Bool {
        let s = t.filter { $0 != " " }
        guard s.count >= 3, let c = s.first, "-*_".contains(c) else { return false }
        return s.allSatisfy { $0 == c }
    }

    /// A line that is only `![alt](url)`.
    static func image(_ t: String) -> MarkdownBlock? {
        guard t.hasPrefix("!["), t.hasSuffix(")"), let mid = t.range(of: "](") else { return nil }
        let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<mid.lowerBound])
        var url = String(t[mid.upperBound..<t.index(before: t.endIndex)])
        if let sp = url.firstIndex(of: " ") { url = String(url[..<sp]) } // drop "title"
        guard !url.isEmpty, !alt.contains("]") else { return nil }
        return .image(alt: alt, url: url)
    }

    static func listItem(_ line: String) -> MarkdownBlock.ListItem? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, "-*+".contains(t.first!), t.dropFirst().first == " " {
            var body = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
            var marker = "•"
            if body.hasPrefix("[ ] ") { marker = "☐"; body = String(body.dropFirst(4)) }
            else if body.lowercased().hasPrefix("[x] ") { marker = "☑"; body = String(body.dropFirst(4)) }
            return .init(depth: indent / 2, marker: marker, text: body)
        }
        let digits = t.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 9 {
            let rest = t.dropFirst(digits.count)
            if (rest.hasPrefix(". ") || rest.hasPrefix(") ")) {
                return .init(depth: indent / 2, marker: "\(digits).",
                             text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var out: [String] = [], cur = ""
        var prev: Character?
        for c in t {
            if c == "|" && prev != "\\" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(c) }
            prev = c
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    static func separator(_ line: String) -> [MarkdownBlock.Align]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.allSatisfy({ "|-: ".contains($0) }) else { return nil }
        let cs = cells(t)
        var out: [MarkdownBlock.Align] = []
        for c in cs {
            guard c.contains("-"), c.allSatisfy({ "-:".contains($0) }) else { return nil }
            out.append(c.hasPrefix(":") && c.hasSuffix(":") ? .center : c.hasSuffix(":") ? .trailing : .leading)
        }
        return out
    }
}
