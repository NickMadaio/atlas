import SwiftUI

/*
 Code, as it appears in real course material.

 A CS lecture's notes are mostly code, and a wall of one-colour monospace is
 close to unreadable. The highlighting here is deliberately shallow — keywords,
 strings, numbers, comments — because that is the level at which colour actually
 helps you find the line you want, and anything deeper means shipping a parser
 per language and getting it subtly wrong.

 Unknown languages fall through to strings, numbers and comments only, which is
 correct for almost everything rather than wrong for one thing.
*/

struct AtlasCodeBlock: View {
    let language: String
    let code: String
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !language.isEmpty {
                AtlasMicroLabel(text: language, size: 9)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(CodeHighlighter.highlight(code, language: language, theme: theme))
                    .font(.system(size: 13.5, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        }
    }
}

enum CodeHighlighter {
    /// Kept small on purpose: these are the words that carry the shape of a
    /// program, and colouring every identifier would make the shape harder to
    /// see rather than easier.
    static let keywords: [String: Set<String>] = [
        "python": [
            "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and",
            "or", "import", "from", "as", "with", "try", "except", "finally", "raise", "assert",
            "lambda", "yield", "pass", "break", "continue", "global", "nonlocal", "del", "is",
            "None", "True", "False", "async", "await", "self"
        ],
        "swift": [
            "func", "let", "var", "return", "if", "else", "guard", "for", "in", "while", "switch",
            "case", "default", "struct", "class", "enum", "protocol", "extension", "import",
            "throws", "try", "catch", "throw", "async", "await", "init", "self", "nil", "true",
            "false", "private", "public", "internal", "static", "some", "where", "defer"
        ],
        "javascript": [
            "function", "const", "let", "var", "return", "if", "else", "for", "while", "switch",
            "case", "default", "class", "extends", "import", "from", "export", "async", "await",
            "try", "catch", "finally", "throw", "new", "this", "null", "undefined", "true", "false"
        ]
    ]

    static let commentPrefixes: [String: [String]] = [
        "python": ["#"],
        "swift": ["//"],
        "javascript": ["//"]
    ]

    static func canonicalLanguage(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "python", "py", "python3": "python"
        case "swift": "swift"
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": "javascript"
        default: nil
        }
    }

    static func highlight(_ code: String, language: String, theme: AtlasPalette) -> AttributedString {
        let canonical = canonicalLanguage(language)
        let words = canonical.flatMap { keywords[$0] } ?? []
        // Both comment styles when the language is unknown: guessing wrong
        // colours one line, guessing nothing leaves every line flat.
        let comments = canonical.flatMap { commentPrefixes[$0] } ?? ["#", "//"]

        var output = AttributedString()
        for (index, line) in code.components(separatedBy: .newlines).enumerated() {
            if index > 0 { output.append(AttributedString("\n")) }
            output.append(highlightLine(line, words: words, comments: comments, theme: theme))
        }
        return output
    }

    private static func highlightLine(
        _ line: String,
        words: Set<String>,
        comments: [String],
        theme: AtlasPalette
    ) -> AttributedString {
        var output = AttributedString()
        var token = ""
        var index = line.startIndex

        func flushToken() {
            guard !token.isEmpty else { return }
            var piece = AttributedString(token)
            if words.contains(token) {
                piece.foregroundColor = theme.primary
                piece.font = .system(size: 13.5, weight: .semibold, design: .monospaced)
            } else if token.first?.isNumber == true, token.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }) {
                piece.foregroundColor = theme.highlight
            } else {
                piece.foregroundColor = theme.textPrimary
            }
            output.append(piece)
            token = ""
        }

        while index < line.endIndex {
            let character = line[index]

            // A comment runs to end of line; nothing inside it is code.
            if let marker = comments.first(where: { line[index...].hasPrefix($0) }) {
                flushToken()
                var rest = AttributedString(String(line[index...]))
                rest.foregroundColor = theme.textSecondary
                rest.font = .system(size: 13.5, design: .monospaced).italic()
                output.append(rest)
                _ = marker
                return output
            }

            if character == "\"" || character == "'" {
                flushToken()
                var literal = String(character)
                var cursor = line.index(after: index)
                var escaped = false
                while cursor < line.endIndex {
                    let next = line[cursor]
                    literal.append(next)
                    cursor = line.index(after: cursor)
                    if escaped { escaped = false; continue }
                    if next == "\\" { escaped = true; continue }
                    if next == character { break }
                }
                var piece = AttributedString(literal)
                piece.foregroundColor = theme.warmAccent
                output.append(piece)
                index = cursor
                continue
            }

            if character.isLetter || character.isNumber || character == "_" {
                token.append(character)
            } else {
                flushToken()
                var piece = AttributedString(String(character))
                piece.foregroundColor = theme.textSecondary
                output.append(piece)
            }
            index = line.index(after: index)
        }
        flushToken()
        return output
    }
}

/// Inline Markdown with `code` rendered as a chip.
///
/// `AttributedString(markdown:)` marks inline code but leaves it looking like
/// ordinary text at this size. Course material is full of `try`, `except`,
/// `ValueError` — names that have to be visually separate from the sentence
/// around them or the sentence stops parsing.
struct InlineMarkdownText: View {
    let source: String
    var size: CGFloat = 15.5
    var weight: Font.Weight = .regular
    @Environment(\.atlasPalette) private var theme

    var body: some View { Text(attributed) }

    private var attributed: AttributedString {
        guard var value = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(source)
        }
        for run in value.runs where run.inlinePresentationIntent?.contains(.code) == true {
            value[run.range].font = .system(size: size - 1, weight: .medium, design: .monospaced)
            value[run.range].foregroundColor = theme.primary
            value[run.range].backgroundColor = theme.tintSurface
        }
        return value
    }
}
