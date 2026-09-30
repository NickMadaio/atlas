import Foundation
import SwiftData

/*
 What Atlas knows about a class before it writes a word.

 The failure this exists to stop: a Python course briefly mentions Java, and a
 model with no idea what the course is decides Java is the subject. It is not a
 transcription bug and it is not fixable by a better prompt alone — the model is
 missing the one fact that makes the transcript readable.

 So the student can state that fact once, per course, and it is placed in front
 of the model on every lecture: standing context outranks a transcript, because
 the transcript is a guess at sounds and the context is not.
*/

/// Standing facts about one course, written by the student.
///
/// Keyed by collection: the folder IS the course, so context follows the class
/// rather than any single recording.
@Model
public final class AtlasCourseContextRecord {
    @Attribute(.unique) public var id: String
    public var collectionID: String
    /// Plain language. "Everything is Python 3. We use pytest and bare assert
    /// statements. The professor's name is …"
    public var briefing: String
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        collectionID: String,
        briefing: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.collectionID = collectionID
        self.briefing = briefing
        self.updatedAt = updatedAt
    }
}

public struct AtlasCourseContextSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let collectionID: String
    public let briefing: String
    public let updatedAt: Date

    public init(id: String, collectionID: String, briefing: String, updatedAt: Date) {
        self.id = id
        self.collectionID = collectionID
        self.briefing = briefing
        self.updatedAt = updatedAt
    }

    public var hasBriefing: Bool {
        briefing.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
}

/// Everything the model is told before it reads a transcript.
///
/// Assembled from three places, deliberately separate because they carry
/// different authority: the course briefing is always true, the lecture note is
/// true for this recording, and reference material is quoted text that may be
/// out of date.
public struct LectureBriefing: Sendable, Hashable {
    /// How the class is named in Atlas, full path: "School › CS 2100".
    public let coursePath: String
    /// Standing facts about the course.
    public let courseBriefing: String
    /// Something about this recording in particular, including a correction
    /// after reading notes that got something wrong.
    public let lectureNote: String
    /// Syllabus, course outline, anything attached to the course itself.
    public let references: [LectureAttachmentText]

    /// Reference material is quoted, so it has to be bounded: a whole syllabus
    /// in every request would crowd out the transcript it exists to explain.
    public static let referenceCharacterBudget = 6_000

    public init(
        coursePath: String = "",
        courseBriefing: String = "",
        lectureNote: String = "",
        references: [LectureAttachmentText] = []
    ) {
        self.coursePath = coursePath
        self.courseBriefing = courseBriefing
        self.lectureNote = lectureNote
        self.references = references
    }

    public static let none = LectureBriefing()

    public var isEmpty: Bool { promptBlock == nil }

    /// The context block placed in front of every request about this lecture,
    /// or nil when there is nothing to say. Nil rather than an empty heading:
    /// a section titled "what you know about this course" with nothing under it
    /// invites a small model to fill it in.
    public var promptBlock: String? {
        var lines: [String] = []

        let path = coursePath.trimmed
        if !path.isEmpty {
            lines.append("Course: \(path)")
        }

        let briefing = courseBriefing.trimmed
        if !briefing.isEmpty {
            lines.append("")
            lines.append("Standing facts about this course, written by the student:")
            lines.append(quoted(briefing))
        }

        let note = lectureNote.trimmed
        if !note.isEmpty {
            lines.append("")
            lines.append("About this recording in particular:")
            lines.append(quoted(note))
        }

        let referenceBlock = referenceText
        if !referenceBlock.isEmpty {
            lines.append("")
            lines.append("From the course's own material (syllabus, outline, reference):")
            lines.append(referenceBlock)
        }

        guard lines.contains(where: { !$0.trimmed.isEmpty && !$0.hasPrefix("Course: ") }) || !path.isEmpty else {
            return nil
        }
        // A course name on its own is worth stating, but only alongside
        // something the model can actually act on.
        guard !briefing.isEmpty || !note.isEmpty || !referenceBlock.isEmpty else { return nil }

        return lines.joined(separator: "\n")
    }

    /// Reference text, oldest first, cut at the budget on a document boundary
    /// so no quoted excerpt ends mid-sentence without saying so.
    private var referenceText: String {
        var blocks: [String] = []
        var used = 0

        for reference in references {
            let text = reference.text.trimmed
            guard text.count >= 40 else { continue }
            let remaining = Self.referenceCharacterBudget - used
            guard remaining > 200 else {
                blocks.append("(Further course material was left out of this request for length.)")
                break
            }
            let kept = text.count <= remaining
                ? text
                : String(text.prefix(remaining)) + "\n…(cut for length)"
            blocks.append("--- \(reference.name) ---\n\(kept)")
            used += kept.count
        }
        return blocks.joined(separator: "\n\n")
    }

    /// Student prose is quoted rather than inlined, so a line that happens to
    /// read like an instruction cannot be mistaken for one of ours.
    private func quoted(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { "> " + $0.trimmed }
            .joined(separator: "\n")
    }
}
