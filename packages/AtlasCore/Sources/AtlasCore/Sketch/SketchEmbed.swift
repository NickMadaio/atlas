import Foundation

/// How a note carries a sketch.
///
/// A saved sketch is a file of its own (`Atlas/Sketches/<id>.json`, the full
/// vector page). A note refers to it with one line of ordinary Markdown image
/// syntax, so the note stays plain text that search, the assistant and the
/// agent bridge read like any other — and any other Markdown reader still
/// shows the word "Sketch" instead of garbage.
public enum SketchEmbed {
    public static let scheme = "atlas-sketch"
    public static let sectionHeading = "## Sketches"

    public static func markdown(for id: UUID) -> String {
        "![Sketch](\(scheme)://\(id.uuidString.lowercased()))"
    }

    /// The sketch a line embeds, when the line is nothing but an embed.
    public static func sketchID(inLine line: String) -> UUID? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "![Sketch](\(scheme)://"
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(")") else { return nil }
        return UUID(uuidString: String(trimmed.dropFirst(prefix.count).dropLast()))
    }

    /// Returns `body` with the sketch filed under its `## Sketches` section,
    /// creating that section at the end when the note has none.
    public static func appending(_ id: UUID, caption: String, to body: String) -> String {
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = (cleanCaption.isEmpty ? "" : "**\(cleanCaption)**\n\n") + markdown(for: id) + "\n"

        let lines = body.components(separatedBy: "\n")
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == sectionHeading }) else {
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let lead = trimmedBody.isEmpty ? "" : body.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + "\n\n"
            return lead + sectionHeading + "\n\n" + entry
        }

        let nextHeading = lines[(headingIndex + 1)...].firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ")
        }
        let sectionEnd = nextHeading ?? lines.count
        let section = Array(lines[headingIndex..<sectionEnd])
        let keptSection = Array(section.reversed().drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }.reversed())
        let entryLines = entry.components(separatedBy: "\n")
        let rebuilt = keptSection + [""] + entryLines
        let rest = Array(lines[sectionEnd...])
        return (Array(lines[..<headingIndex]) + rebuilt + rest).joined(separator: "\n")
    }
}

extension SketchPage {
    /// The rectangle around everything drawn, widened by each stroke's half
    /// width and `padding`; nil for an empty page.
    public func inkBounds(padding: Double) -> SketchRect? {
        let edges = strokes.flatMap { stroke in
            stroke.points.map { (point: $0, reach: stroke.width / 2 + padding) }
        }
        guard !edges.isEmpty else { return nil }
        let minX = edges.map { $0.point.x - $0.reach }.min()!
        let minY = edges.map { $0.point.y - $0.reach }.min()!
        let maxX = edges.map { $0.point.x + $0.reach }.max()!
        let maxY = edges.map { $0.point.y + $0.reach }.max()!
        return SketchRect(minX: minX, minY: minY, width: maxX - minX, height: maxY - minY)
    }
}
