import Foundation

/*
 The block structure of a note.

 Split out of the renderer because it grew two things the old one could not do,
 and both show up constantly in real lecture material:

 - Nested lists. A sub-point under a point is how every set of slides is
   written. Flattening them, which is what the old parser did, loses the one
   thing the indentation was carrying.
 - Embeds. `![[Some note]]` alone on a line opens that note in place, so a full
   work-through can live inside the section that needs it.
*/

public enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(MarkdownList)
    case quote(String)
    case code(language: String, content: String)
    case table(headers: [String], rows: [[String]])
    case divider
    /// Another note, opened where this line sits.
    case embed(title: String)
    /// A saved trackpad sketch, drawn where this line sits.
    case sketch(id: UUID)
    /// A set-aside block written `> [!kind] text`, the way Obsidian writes
    /// callouts. `answer` is the one that matters here: it keeps a quiz answer
    /// in the note without putting it in front of you while you are answering.
    case callout(kind: String, text: String)
}

public struct MarkdownList {
    public let ordered: Bool
    public let items: [MarkdownListItem]
}

public struct MarkdownListItem {
    public let text: String
    /// Set only for `- [ ]` / `- [x]` lines.
    public let checked: Bool?
    public let sublist: MarkdownList?
}

public enum MarkdownBlockParser {
    /// Indentation of two spaces or more starts a nested level. Four is the
    /// common convention but models and people both write two, and reading two
    /// as "not nested" loses the structure entirely.
    public static let indentPerLevel = 2

    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { index += 1; continue }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index]); index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language, content: codeLines.joined(separator: "\n")))
                continue
            }

            if let sketch = SketchEmbed.sketchID(inLine: line) {
                blocks.append(.sketch(id: sketch)); index += 1; continue
            }
            if let title = AtlasNoteLinks.embedTitle(inLine: line) {
                blocks.append(.embed(title: title)); index += 1; continue
            }
            if let heading = heading(from: trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text)); index += 1; continue
            }
            if isDivider(trimmed) { blocks.append(.divider); index += 1; continue }

            if isTableHeader(at: index, lines: lines) {
                let headers = tableCells(lines[index])
                index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index])); index += 1
                }
                blocks.append(.table(headers: headers, rows: rows)); continue
            }

            if let callout = calloutStart(trimmed) {
                var body = [callout.text]
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">"), calloutStart(candidate) == nil else { break }
                    body.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(
                    .callout(
                        kind: callout.kind,
                        text: body.filter { !$0.isEmpty }.joined(separator: " ")
                    )
                )
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: " "))); continue
            }

            if let marker = listMarker(line) {
                blocks.append(.list(parseList(lines, &index, indent: marker.indent, ordered: marker.ordered)))
                continue
            }

            var paragraph: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty { break }
                if startsBlock(lines[index], index: index, lines: lines) { break }
                paragraph.append(candidate); index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }

    // MARK: - Lists

    public struct ListMarker {
        let indent: Int
        let ordered: Bool
        let text: String
    }

    /// Reads one list line, or nil when the line is not one.
    public static func listMarker(_ line: String) -> ListMarker? {
        var indent = 0
        var rest = Substring(line)
        while let first = rest.first, first == " " || first == "\t" {
            indent += first == "\t" ? 4 : 1
            rest = rest.dropFirst()
        }
        let text = String(rest)

        for prefix in ["- ", "* ", "+ "] where text.hasPrefix(prefix) {
            return ListMarker(indent: indent, ordered: false, text: String(text.dropFirst(2)))
        }
        // A bullet character pasted from a slide deck is still a bullet.
        if text.hasPrefix("\u{2022} ") || text.hasPrefix("\u{25E6} ") {
            return ListMarker(indent: indent, ordered: false, text: String(text.dropFirst(2)))
        }
        guard let separator = text.firstIndex(where: { $0 == "." || $0 == ")" }), separator != text.startIndex else {
            return nil
        }
        let number = text[..<separator]
        guard number.count <= 3, number.allSatisfy(\.isNumber) else { return nil }
        let remainder = text[text.index(after: separator)...]
        guard remainder.first == " " else { return nil }
        return ListMarker(indent: indent, ordered: true, text: String(remainder.dropFirst()))
    }

    /// Builds one level of a list and recurses into anything indented under it.
    ///
    /// Always consumes at least the line it was called on, so a malformed run
    /// cannot spin: the loop's entry condition is true on arrival.
    public static func parseList(
        _ lines: [String],
        _ index: inout Int,
        indent: Int,
        ordered: Bool
    ) -> MarkdownList {
        var items: [MarkdownListItem] = []

        while index < lines.count, let marker = listMarker(lines[index]), marker.indent >= indent {
            if marker.indent >= indent + indentPerLevel, !items.isEmpty {
                let sublist = parseList(lines, &index, indent: marker.indent, ordered: marker.ordered)
                let last = items.removeLast()
                items.append(MarkdownListItem(text: last.text, checked: last.checked, sublist: sublist))
                continue
            }
            // A different kind of marker at this level is a new list, not this one.
            if marker.ordered != ordered, marker.indent == indent, !items.isEmpty { break }
            index += 1
            items.append(checklistItem(marker.text))
        }
        return MarkdownList(ordered: ordered, items: items)
    }

    public static func checklistItem(_ text: String) -> MarkdownListItem {
        if text.hasPrefix("[ ] ") {
            return MarkdownListItem(text: String(text.dropFirst(4)), checked: false, sublist: nil)
        }
        if text.lowercased().hasPrefix("[x] ") {
            return MarkdownListItem(text: String(text.dropFirst(4)), checked: true, sublist: nil)
        }
        return MarkdownListItem(text: text, checked: nil, sublist: nil)
    }

    // MARK: - Line shapes

    /// Reads `> [!kind] text`, or nil when the line is an ordinary quote.
    public static func calloutStart(_ line: String) -> (kind: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("[!"), let close = rest.firstIndex(of: "]") else { return nil }
        let kind = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<close])
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !kind.isEmpty, kind.count <= 24 else { return nil }
        let text = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return (kind, text)
    }

    public static func heading(from line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    public static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let cells = tableCells(lines[index + 1])
        return !cells.isEmpty && cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    public static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && (compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" })
    }

    public static func startsBlock(_ rawLine: String, index: Int, lines: [String]) -> Bool {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("```")
            || heading(from: line) != nil
            || isDivider(line)
            || line.hasPrefix(">")
            || listMarker(rawLine) != nil
            || AtlasNoteLinks.embedTitle(inLine: rawLine) != nil
            || SketchEmbed.sketchID(inLine: rawLine) != nil
            || isTableHeader(at: index, lines: lines)
    }
}
