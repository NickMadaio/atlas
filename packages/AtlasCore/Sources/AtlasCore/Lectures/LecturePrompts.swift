import Foundation

/// Assembles what the local model is actually sent.
///
/// The instructions themselves live in `LectureSkill` and can be edited from
/// Settings. This type only composes them: skill file, then the context block
/// when a course has one, then the detail guidance, then the JSON schema for
/// the stages that must return it.
///
/// The schema is appended here rather than stored in the editable file on
/// purpose — an edit that dropped it would silently break every note.
public enum LecturePrompts {

    // MARK: - System prompts

    public static func extractionSystem(
        skills: LectureSkillSet = .standard,
        briefing: LectureBriefing = .none,
        outline: LectureSlideOutline? = nil,
        format: NoteFormatPreferences = .standard
    ) -> String {
        compose(
            instructions: skills.instructions(for: .noteWriting),
            context: [contextSection(skills: skills, briefing: briefing), outline?.promptBlock]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                .nilWhenEmpty,
            trailing: format.detail.writingGuidance,
            skills: skills
        )
    }

    public static func attachmentSystem(
        skills: LectureSkillSet = .standard,
        briefing: LectureBriefing = .none
    ) -> String {
        compose(
            instructions: skills.instructions(for: .attachments),
            context: contextSection(skills: skills, briefing: briefing),
            trailing: nil,
            skills: skills
        )
    }

    public static func consolidationSystem(
        skills: LectureSkillSet = .standard,
        briefing: LectureBriefing = .none,
        outline: LectureSlideOutline? = nil,
        format: NoteFormatPreferences = .standard
    ) -> String {
        compose(
            instructions: skills.instructions(for: .consolidation),
            context: [contextSection(skills: skills, briefing: briefing), outline?.promptBlock]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                .nilWhenEmpty,
            trailing: format.detail.writingGuidance,
            skills: skills
        )
    }

    public static func filingSystem(skills: LectureSkillSet = .standard) -> String {
        skills.instructions(for: .filing)
    }

    public static func outlineSystem(skills: LectureSkillSet = .standard) -> String {
        compose(instructions: skills.instructions(for: .outline), context: nil, trailing: nil, skills: skills)
    }

    public static func reviewSystem(
        skills: LectureSkillSet = .standard,
        briefing: LectureBriefing = .none,
        outline: LectureSlideOutline? = nil
    ) -> String {
        compose(
            instructions: skills.instructions(for: .review),
            context: [contextSection(skills: skills, briefing: briefing), outline?.promptBlock]
                .compactMap { $0 }
                .joined(separator: "\n\n")
                .nilWhenEmpty,
            trailing: nil,
            skills: skills
        )
    }

    public static func quizSystem(skills: LectureSkillSet = .standard) -> String {
        compose(instructions: skills.instructions(for: .quiz), context: nil, trailing: nil, skills: skills)
    }

    /// Revision reuses the consolidation instructions — it is the same job,
    /// merging a draft with a list of things to change — plus the change list.
    public static func revisionSystem(
        skills: LectureSkillSet = .standard,
        briefing: LectureBriefing = .none,
        format: NoteFormatPreferences = .standard
    ) -> String {
        compose(
            instructions: """
            You are given a draft of one lecture's notes and a list of things a reviewer found wrong with it. Produce the corrected notes.

            Apply every correction. A correction with no replacement text means remove the thing entirely — do not soften it, do not keep a trace of it. A correction of kind "missing" means add what it names. A correction of kind "noise" means the material came from students talking during an activity: remove it from the notes, and make sure the activity itself is recorded once in "activities".

            Change nothing else. Everything the reviewer did not mention stays exactly as it was, in the same order.

            Reply with one JSON object in the lecture-notes shape and nothing else.
            """,
            context: contextSection(skills: skills, briefing: briefing),
            trailing: format.detail.writingGuidance,
            skills: skills
        )
    }

    /// The context rules plus the course's own facts, or nil when the class has
    /// nothing saved. Nil rather than empty: a heading with nothing under it
    /// invites a small model to invent something to put there.
    static func contextSection(skills: LectureSkillSet, briefing: LectureBriefing) -> String? {
        guard let facts = briefing.promptBlock else { return nil }
        return """
        WHAT YOU ALREADY KNOW ABOUT THIS COURSE

        \(skills.instructions(for: .context))

        \(facts)
        """
    }

    /// Every request opens with the house style, then the pass's own
    /// instructions, then what Atlas knows about the course, then any length
    /// guidance. The order is deliberate: the goal first, the job second, the
    /// facts third.
    private static func compose(
        instructions: String,
        context: String?,
        trailing: String?,
        skills: LectureSkillSet = .standard
    ) -> String {
        [skills.instructions(for: .houseStyle), instructions, context, trailing]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Schema

    public static let schemaDescription = """
    {
      "title": "short specific title for this lecture",
      "courseName": "the course this belongs to, if stated or obvious",
      "courseCode": "course code such as CS2100, if stated",
      "category": "Lecture",
      "summary": "3-5 sentences on what this lecture was actually about",
      "topics": ["short topic labels"],
      "keyPoints": ["the things worth remembering, one per item"],
      "outline": [{"heading": "section of the lecture", "points": ["what was said in it"]}],
      "glossary": [{
        "term": "term the lecturer used",
        "shortDefinition": "one sentence a student can hold in their head",
        "deepExplanation": "a full paragraph that actually explains it, including standard background",
        "whyItMatters": "why this matters in this course"
      }],
      "formulas": [{"name": "name", "expression": "the formula", "meaning": "what it means"}],
      "reviewQuestions": ["questions to test understanding of this material"],
      "actionItems": ["anything the student was told to do"],
      "uncertainties": ["anything unclear in the audio, or that needs checking elsewhere"],
      "deepDives": [{
        "title": "the one idea this note is about",
        "section": "the exact outline heading this belongs under, or empty",
        "summary": "one line on what it covers",
        "markdown": "a full Markdown explanation, several paragraphs, with ## headings"
      }],
      "activities": [{
        "title": "what the class did, named",
        "task": "what they were asked to do",
        "conclusion": "what the lecturer drew out of it afterwards, or empty",
        "whenLabel": "roughly when in the recording, or empty"
      }],
      "otherVoices": [{
        "speaker": "A student | Someone in the room | Unclear",
        "content": "what they said",
        "kind": "question | answer | comment | correction",
        "matters": "why this is worth keeping, or empty"
      }]
    }
    """

    // MARK: - User prompts

    public static func extractionUser(
        chunk: TranscriptChunk,
        totalChunks: Int,
        hint: String?
    ) -> String {
        var header = "Transcript part \(chunk.index + 1) of \(totalChunks), covering \(chunk.rangeLabel) of the recording."
        if let hint, !hint.trimmed.isEmpty {
            header += "\nThe student labelled this recording: \(hint.trimmed)"
        }
        return """
        \(header)

        Return JSON in exactly this shape:
        \(schemaDescription)

        Transcript:
        \"\"\"
        \(chunk.text)
        \"\"\"
        """
    }

    public static func attachmentUser(chunk: LectureAttachmentChunk, hint: String?) -> String {
        var header = "Attached material \"\(chunk.documentName)\", \(chunk.pageLabel)"
        if chunk.total > 1 {
            header += " (part \(chunk.index + 1) of \(chunk.total))"
        }
        header += "."
        header += "\nCite anything you take from it as \"(\(chunk.documentName), \(chunk.pageNoun) N)\"."
        if let hint, !hint.trimmed.isEmpty {
            header += "\nThe student labelled the lecture: \(hint.trimmed)"
        }
        return """
        \(header)

        Return JSON in exactly this shape:
        \(schemaDescription)

        Material:
        \"\"\"
        \(chunk.text)
        \"\"\"
        """
    }

    public static func outlineUser(text: String, documentNames: [String]) -> String {
        """
        The attached material for one lecture: \(documentNames.joined(separator: ", ")).

        Return JSON in exactly this shape:
        {
          "title": "the lecture's title as the deck gives it",
          "objectives": ["learning objectives the deck states, verbatim"],
          "sections": [{"heading": "section name", "startsAt": "slide 5"}],
          "terms": [{"term": "exactly as written", "definition": "the deck's own words, or empty"}],
          "processes": ["anything written as steps or a formula"]
        }

        Material:
        \"\"\"
        \(text)
        \"\"\"
        """
    }

    public static func reviewUser(structure: LectureStructure, transcriptExcerpt: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = (try? encoder.encode(structure)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        The draft notes:
        \(payload)

        The transcript they were written from:
        \"\"\"
        \(transcriptExcerpt)
        \"\"\"

        List what is wrong. Reply with one JSON object and nothing else.
        """
    }

    public static func revisionUser(structure: LectureStructure, review: LectureReview) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let draft = (try? encoder.encode(structure)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let corrections = (try? encoder.encode(review)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        The draft:
        \(draft)

        What the reviewer found:
        \(corrections)

        Return the corrected notes in the same shape:
        \(schemaDescription)
        """
    }

    public static func quizUser(structure: LectureStructure) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = (try? encoder.encode(structure)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        The finished notes for one lecture:
        \(payload)

        Write the quiz. Reply with one JSON object and nothing else.
        """
    }

    public static func consolidationUser(merged: LectureStructure, hint: String?) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = (try? encoder.encode(merged)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var header = "These are the merged notes from every part of one lecture."
        if let hint, !hint.trimmed.isEmpty {
            header += "\nThe student labelled this recording: \(hint.trimmed)"
        }
        return """
        \(header)

        Produce one final JSON object in the same shape. Write a real title and a summary that \
        covers the whole lecture rather than only its opening.

        \(schemaDescription)

        Merged notes:
        \(payload)
        """
    }
}


extension String {
    /// Nil for a string with nothing in it, so an empty section can be dropped
    /// from a prompt rather than appearing as a heading with no content.
    var nilWhenEmpty: String? {
        trimmed.isEmpty ? nil : self
    }
}
