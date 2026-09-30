import Foundation

/// Wiki-style links and embeds between notes.
///
/// Two forms, and the difference matters. `[[Some note]]` is a reference: it
/// says "there is more about this over there" and opens it when clicked.
/// `![[Some note]]` is an embed: the note opens *here*, inside the section that
/// mentions it, without leaving the page. Obsidian draws the same distinction,
/// and it is the right one — a derivation belongs where the topic is, not in an
/// index at the bottom that the reader has to know to visit.
public enum AtlasNoteLinks {
    public static let scheme = "atlas-note"
    /// A title longer than this is not a title; it is a paragraph that happened
    /// to contain two brackets.
    public static let maximumTitleLength = 200

    /// Rewrites `[[Title]]` into ordinary Markdown so the existing renderer
    /// turns it into a real link.
    ///
    /// Embeds are deliberately left alone: `![[Title]]` rewritten the same way
    /// would become `![Title](…)`, which Markdown reads as an image, and the
    /// renderer handles embeds as their own kind of block.
    public static func resolvingWikiLinks(in source: String) -> String {
        var output = ""
        var remainder = Substring(source)

        while let open = remainder.range(of: "[[") {
            guard let close = remainder.range(of: "]]", range: open.upperBound..<remainder.endIndex) else {
                break
            }
            let title = String(remainder[open.upperBound..<close.lowerBound])
            let isEmbed = open.lowerBound > remainder.startIndex
                && remainder[remainder.index(before: open.lowerBound)] == "!"

            output += remainder[remainder.startIndex..<open.lowerBound]

            // A link needs somewhere to point; an empty or over-long target is
            // left as written rather than turned into a dead link.
            if isEmbed {
                output += "[[\(title)]]"
            } else if let encoded = encode(title), !title.isEmpty, title.count <= maximumTitleLength {
                output += "[\(title)](\(scheme):\(encoded))"
            } else {
                output += "[[\(title)]]"
            }
            remainder = remainder[close.upperBound...]
        }
        output += remainder
        return output
    }

    /// Every note title referenced from a body, in order, without duplicates.
    /// Embeds count: an embedded note is referenced, just more strongly.
    public static func referencedTitles(in source: String) -> [String] {
        titles(in: source) { _ in true }
    }

    /// Only the titles written as `![[Title]]`.
    public static func embeddedTitles(in source: String) -> [String] {
        titles(in: source) { $0 }
    }

    private static func titles(in source: String, where include: (Bool) -> Bool) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        var remainder = Substring(source)

        while let open = remainder.range(of: "[[") {
            guard let close = remainder.range(of: "]]", range: open.upperBound..<remainder.endIndex) else {
                break
            }
            let isEmbed = open.lowerBound > remainder.startIndex
                && remainder[remainder.index(before: open.lowerBound)] == "!"
            let title = String(remainder[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if include(isEmbed), !title.isEmpty, title.count <= maximumTitleLength,
               seen.insert(title.lowercased()).inserted {
                found.append(title)
            }
            remainder = remainder[close.upperBound...]
        }
        return found
    }

    /// The title an embed line carries, or nil when the line is something else.
    /// An embed has to be alone on its line — `![[x]]` in the middle of a
    /// sentence is a reference the writer typed oddly, not a request to unfold
    /// a whole note mid-paragraph.
    public static func embedTitle(inLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else { return nil }
        let title = String(trimmed.dropFirst(3).dropLast(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= maximumTitleLength else { return nil }
        return title
    }

    /// The title a link URL points at, or nil for a URL that is not one of ours.
    public static func title(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let raw = url.absoluteString.dropFirst(scheme.count + 1)
        return raw.removingPercentEncoding ?? String(raw)
    }

    /// Writes a reference the way a note should carry one.
    public static func link(to title: String) -> String { "[[\(title)]]" }

    /// Writes an embed: the note opens in place, where this line sits.
    public static func embed(of title: String) -> String { "![[\(title)]]" }

    private static func encode(_ title: String) -> String? {
        title.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
    }
}
