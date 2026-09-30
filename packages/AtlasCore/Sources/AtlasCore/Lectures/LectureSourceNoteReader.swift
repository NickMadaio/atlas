import Foundation

/*
 Reading a lecture back out of the note it wrote.

 The source note was designed to be the complete record of one recording — the
 details table, the transcript with timecodes, everything. That makes it a
 durable backup nobody planned: if the lecture row is lost while the note
 survives, the recording can be rebuilt from its own output.

 That is not hypothetical. Opening this library with a build of Atlas that
 predates the lecture feature migrates the store down to that older model and
 drops the lecture and attachment tables outright. The audio stays on disk, the
 notes stay in the library, and only the rows joining them go.
*/
public enum LectureSourceNoteReader {
    /// What the details table at the top of a source note records.
    public struct Details: Sendable, Equatable {
        public let lectureID: String
        public let courseTitle: String
        public let recordedAt: Date?
        public let durationSeconds: Double
        public let transcriptionEngine: String
        public let modelIdentifier: String?
        public let studyTitle: String
        public let attachmentNames: [String]
    }

    /// Reads the details table. Nil when there is no lecture id, because
    /// without one nothing can be matched to its audio.
    public static func details(in markdown: String) -> Details? {
        let rows = tableRows(in: markdown)
        guard let rawID = rows["Lecture ID"] else { return nil }
        let lectureID = rawID.trimmingCharacters(in: CharacterSet(charactersIn: "`  "))
        guard !lectureID.isEmpty else { return nil }

        let model = rows["Notes written by"]?.trimmed
        return Details(
            lectureID: lectureID,
            courseTitle: rows["Course"]?.trimmed ?? "",
            recordedAt: rows["Recorded"].flatMap(date(from:)),
            durationSeconds: rows["Length"].map(seconds(from:)) ?? 0,
            transcriptionEngine: rows["Transcription"]?.trimmed ?? "Unknown",
            // The builder writes this phrase when nothing enriched the notes.
            modelIdentifier: (model?.hasPrefix("No local model") ?? true) ? nil : model,
            studyTitle: rows["Student note"]?.trimmed ?? "",
            attachmentNames: rows["Attached material"]?
                .components(separatedBy: ",")
                .map { $0.trimmed }
                .filter { !$0.isEmpty } ?? []
        )
    }

    /// The transcript, with its timecodes turned back into segments.
    ///
    /// The end of each segment is the start of the next, which is what the
    /// recogniser's spans amount to once they have been rendered to text. The
    /// last one is given a nominal length rather than zero so it is not treated
    /// as empty.
    public static func transcript(in markdown: String) -> (text: String, segments: [AtlasLectureSegment]) {
        guard let range = markdown.range(of: "\n## Full transcript") else { return ("", []) }
        let body = markdown[range.upperBound...]
        var starts: [(Double, String)] = []

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard trimmed.hasPrefix("**["), let close = trimmed.range(of: "]**") else { continue }
            let timecode = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<close.lowerBound])
            let text = String(trimmed[close.upperBound...]).trimmed
            guard !text.isEmpty else { continue }
            starts.append((seconds(from: timecode), text))
        }

        guard !starts.isEmpty else {
            // A transcript written without timing is still a transcript.
            let text = body
                .components(separatedBy: .newlines)
                .map { $0.trimmed }
                .filter { !$0.isEmpty && !$0.hasPrefix("_") }
                .joined(separator: " ")
                .trimmed
            return (text, [])
        }

        var segments: [AtlasLectureSegment] = []
        for (index, entry) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].0 : entry.0 + 3
            segments.append(AtlasLectureSegment(start: entry.0, end: end, text: entry.1))
        }
        return (segments.map(\.text).joined(separator: " "), segments)
    }

    // MARK: - Parsing

    /// Every `| Field | Value |` row above the first section that is not a
    /// table, keyed by field.
    static func tableRows(in markdown: String) -> [String: String] {
        var rows: [String: String] = [:]
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { continue }
            let cells = trimmed
                .dropFirst()
                .dropLast()
                .components(separatedBy: "|")
                .map { $0.trimmed }
            guard cells.count == 2, !cells[0].isEmpty else { continue }
            // The separator row, and the header, are not data.
            guard !cells[0].allSatisfy({ $0 == "-" || $0 == ":" }) else { continue }
            guard cells[0] != "Field" else { continue }
            if rows[cells[0]] == nil { rows[cells[0]] = cells[1] }
        }
        return rows
    }

    /// "1:29:30" or "12:05" back into seconds.
    static func seconds(from timecode: String) -> Double {
        let parts = timecode.trimmed.components(separatedBy: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// The format `LectureNoteBuilder.dateLabel` produces. Parsed in a fixed
    /// locale, because the note may have been written on a machine set to a
    /// different one and a wrong date is worse than no date.
    static func date(from label: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["EEEE, MMM d, y 'at' h:mm a", "EEEE, MMM d, y, h:mm a", "MMM d, y 'at' h:mm a"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: label.trimmed) { return date }
        }
        return nil
    }
}
