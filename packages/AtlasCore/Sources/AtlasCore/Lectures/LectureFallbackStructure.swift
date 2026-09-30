import Foundation

/// Builds a usable structure from the transcript alone.
///
/// A lecture happens once. If no local model is reachable, or the model
/// returns nothing usable, Atlas still files a real note rather than dropping
/// the recording on the floor — the transcript is kept, a rough outline is
/// derived from it, and the note says plainly that no model wrote it.
public enum LectureFallbackStructure {
    public static func build(
        segments: [AtlasLectureSegment],
        transcriptText: String,
        hint: String?,
        durationSeconds: Double
    ) -> LectureStructure {
        let sentences = self.sentences(in: transcriptText)
        let hintValue = (hint ?? "").trimmed

        return LectureStructure(
            title: "",
            courseName: hintValue,
            courseCode: "",
            category: AtlasLectureDocumentRole.study.categoryName,
            summary: summary(from: sentences, durationSeconds: durationSeconds),
            topics: [],
            keyPoints: keyPoints(from: sentences),
            outline: outline(from: segments, sentences: sentences),
            glossary: glossary(from: sentences),
            formulas: [],
            reviewQuestions: [],
            actionItems: [],
            uncertainties: [
                "No local model was available when this lecture was filed, so these notes were derived from the transcript by simple text rules. The structure is rough and the terms below may be incomplete.",
                "Re-run note writing from the Lectures list once a local model is available to replace this with a full set of notes."
            ]
        ).normalized()
    }

    static func summary(from sentences: [String], durationSeconds: Double) -> String {
        let opening = sentences.prefix(3).joined(separator: " ")
        guard !opening.isEmpty else {
            return "A \(AtlasLectureSegment.timecode(for: durationSeconds)) recording was transcribed, but no readable speech was found."
        }
        return "Transcript-only notes for a \(AtlasLectureSegment.timecode(for: durationSeconds)) recording. It opens: \(opening)".bounded(900)
    }

    static func keyPoints(from sentences: [String]) -> [String] {
        let signals = [
            "the key", "important", "remember", "the point", "make sure",
            "on the exam", "will be tested", "the main", "in other words",
            "this means", "note that", "for the midterm", "for the final"
        ]
        let matches = sentences.filter { sentence in
            let lowered = sentence.lowercased()
            return signals.contains { lowered.contains($0) }
        }
        return Array(matches.prefix(12))
    }

    /// Time buckets, so a long recording still has navigable sections.
    static func outline(from segments: [AtlasLectureSegment], sentences: [String]) -> [LectureOutlineItem] {
        guard !segments.isEmpty else {
            guard !sentences.isEmpty else { return [] }
            return [LectureOutlineItem(heading: "Transcript highlights", points: Array(sentences.prefix(8)))]
        }

        let chunks = TranscriptChunker.chunks(from: segments, maximumCharacters: 4_000)
        return chunks.prefix(12).map { chunk in
            LectureOutlineItem(
                heading: "Minutes \(chunk.rangeLabel)",
                points: Array(self.sentences(in: chunk.text).prefix(4))
            )
        }
    }

    /// Catches the shapes a lecturer uses when introducing a term.
    static func glossary(from sentences: [String]) -> [LectureGlossaryTerm] {
        let markers = [" is called ", " we call ", " is known as ", " is defined as ", " refers to ", " means that "]
        var terms: [LectureGlossaryTerm] = []

        for sentence in sentences {
            let lowered = sentence.lowercased()
            guard let marker = markers.first(where: { lowered.contains($0) }),
                  let range = lowered.range(of: marker) else { continue }

            let subject = String(sentence[sentence.startIndex..<sentence.index(sentence.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.lowerBound))])
            let predicate = String(sentence[sentence.index(sentence.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: range.upperBound))...])

            let term = marker == " is called " || marker == " we call " || marker == " is known as "
                ? predicate.trimmed
                : subject.trimmed
            let definition = term == predicate.trimmed ? subject.trimmed : predicate.trimmed

            guard term.count >= 3, term.count <= 80, !definition.isEmpty else { continue }
            terms.append(
                LectureGlossaryTerm(
                    term: term,
                    shortDefinition: definition,
                    deepExplanation: "Taken directly from the recording: “\(sentence)” No model expanded this definition.",
                    whyItMatters: ""
                )
            )
            if terms.count == 12 { break }
        }
        return terms
    }

    static func sentences(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".?!"))
            .map { $0.trimmed }
            .filter { $0.count >= 30 && $0.count <= 400 }
    }
}
