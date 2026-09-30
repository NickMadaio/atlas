import Foundation

public enum MarkdownSections {
    public static func parse(_ markdown: String) -> [AtlasSection] {
        let lines = markdown.components(separatedBy: .newlines)
        var sections: [AtlasSection] = []
        var currentTitle = "Overview"
        var currentLines: [String] = []
        var seenHeading = false
        var insideCodeFence = false

        func appendCurrent() {
            let body = currentLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            sections.append(
                AtlasSection(
                    id: uniqueSlug(for: currentTitle, existing: sections.map(\.id)),
                    title: currentTitle,
                    markdown: body
                )
            )
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideCodeFence.toggle()
                currentLines.append(line)
            } else if !insideCodeFence, line.hasPrefix("## ") {
                appendCurrent()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
                seenHeading = true
            } else {
                currentLines.append(line)
            }
        }
        appendCurrent()

        if sections.isEmpty && !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [AtlasSection(id: "overview", title: "Overview", markdown: markdown)]
        }
        if !seenHeading, sections.count == 1 {
            return sections
        }
        return sections
    }

    public static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "section" : collapsed
    }

    private static func uniqueSlug(for value: String, existing: [String]) -> String {
        let base = slug(value)
        guard existing.contains(base) else { return base }
        var suffix = 2
        while existing.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }
}
