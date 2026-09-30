import Foundation

public struct LectureOutlineItem: Codable, Hashable, Sendable {
    public var heading: String
    public var points: [String]

    public init(heading: String, points: [String]) {
        self.heading = heading
        self.points = points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading = container.lenientString(.heading)
        points = container.lenientStrings(.points)
    }
}

public struct LectureGlossaryTerm: Codable, Hashable, Sendable {
    public var term: String
    /// One sentence a student can hold in their head.
    public var shortDefinition: String
    /// The long version, written so an assistant can reason with it later.
    public var deepExplanation: String
    public var whyItMatters: String

    public init(term: String, shortDefinition: String, deepExplanation: String, whyItMatters: String = "") {
        self.term = term
        self.shortDefinition = shortDefinition
        self.deepExplanation = deepExplanation
        self.whyItMatters = whyItMatters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = container.lenientString(.term)
        shortDefinition = container.lenientString(.shortDefinition)
        deepExplanation = container.lenientString(.deepExplanation)
        whyItMatters = container.lenientString(.whyItMatters)
    }
}

public struct LectureFormula: Codable, Hashable, Sendable {
    public var name: String
    public var expression: String
    public var meaning: String

    public init(name: String, expression: String, meaning: String) {
        self.name = name
        self.expression = expression
        self.meaning = meaning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenientString(.name)
        expression = container.lenientString(.expression)
        meaning = container.lenientString(.meaning)
    }
}

/// Something said by someone other than the lecturer.
///
/// A room recording catches students asking and answering questions. That
/// content is often worth keeping — but blended into the lecturer's words it
/// becomes a false record of what was taught, so it is attributed separately.
public struct LectureVoiceNote: Codable, Hashable, Sendable {
    /// Who said it, as far as the audio shows: "A student", "Someone in the
    /// room", "Unclear". Never a guessed name.
    public var speaker: String
    public var content: String
    /// question, answer, comment, or correction.
    public var kind: String
    /// Why it is worth keeping, or empty if it is only context.
    public var matters: String

    public init(speaker: String, content: String, kind: String = "comment", matters: String = "") {
        self.speaker = speaker
        self.content = content
        self.kind = kind
        self.matters = matters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speaker = container.lenientString(.speaker)
        content = container.lenientString(.content)
        kind = container.lenientString(.kind)
        matters = container.lenientString(.matters)
    }
}

/// One idea that earned a note of its own.
///
/// Most of a lecture belongs in the lecture's note. Occasionally something —
/// a derivation, a process with steps, a worked example — needs more room than
/// a bullet, and breaking it out keeps the main note readable while the detail
/// stays one click away.
public struct LectureDeepDive: Codable, Hashable, Sendable {
    public var title: String
    /// The outline heading this belongs under, so the explanation can be
    /// embedded where the topic comes up instead of listed at the end. Empty
    /// when the model did not say, which is common and not an error.
    public var section: String
    public var summary: String
    public var markdown: String

    public init(title: String, section: String = "", summary: String = "", markdown: String) {
        self.title = title
        self.section = section
        self.summary = summary
        self.markdown = markdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenientString(.title)
        section = container.lenientString(.section)
        summary = container.lenientString(.summary)
        markdown = container.lenientString(.markdown)
    }
}

/// Everything a local model is asked to extract from one lecture. Every field
/// is optional in the wire format: a model that omits half the schema still
/// produces a usable note rather than an error.
public struct LectureStructure: Codable, Hashable, Sendable {
    public var title: String
    public var courseName: String
    public var courseCode: String
    public var category: String
    public var summary: String
    public var topics: [String]
    public var keyPoints: [String]
    public var outline: [LectureOutlineItem]
    public var glossary: [LectureGlossaryTerm]
    public var formulas: [LectureFormula]
    public var reviewQuestions: [String]
    public var actionItems: [String]
    /// Points the audio left genuinely unclear. These are the places an
    /// assistant should reach for its own knowledge or the web, and they are
    /// labelled as such in the depth note so nothing gets passed off as
    /// something the lecturer actually said.
    public var uncertainties: [String]
    /// Questions, answers, and remarks from people other than the lecturer.
    public var otherVoices: [LectureVoiceNote]
    /// Ideas that earned a note of their own, linked from the main note.
    public var deepDives: [LectureDeepDive]
    /// Things the class did rather than was told. Recording the activity is
    /// what lets its crosstalk be discarded without losing that it happened.
    public var activities: [LectureActivity]
    /// Questions to test yourself with, written from the finished notes.
    public var quiz: [LectureQuizQuestion]

    public init(
        title: String = "",
        courseName: String = "",
        courseCode: String = "",
        category: String = "",
        summary: String = "",
        topics: [String] = [],
        keyPoints: [String] = [],
        outline: [LectureOutlineItem] = [],
        glossary: [LectureGlossaryTerm] = [],
        formulas: [LectureFormula] = [],
        reviewQuestions: [String] = [],
        actionItems: [String] = [],
        uncertainties: [String] = [],
        otherVoices: [LectureVoiceNote] = [],
        deepDives: [LectureDeepDive] = [],
        activities: [LectureActivity] = [],
        quiz: [LectureQuizQuestion] = []
    ) {
        self.title = title
        self.courseName = courseName
        self.courseCode = courseCode
        self.category = category
        self.summary = summary
        self.topics = topics
        self.keyPoints = keyPoints
        self.outline = outline
        self.glossary = glossary
        self.formulas = formulas
        self.reviewQuestions = reviewQuestions
        self.actionItems = actionItems
        self.uncertainties = uncertainties
        self.otherVoices = otherVoices
        self.deepDives = deepDives
        self.activities = activities
        self.quiz = quiz
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenientString(.title)
        courseName = container.lenientString(.courseName)
        courseCode = container.lenientString(.courseCode)
        category = container.lenientString(.category)
        summary = container.lenientString(.summary)
        topics = container.lenientStrings(.topics)
        keyPoints = container.lenientStrings(.keyPoints)
        reviewQuestions = container.lenientStrings(.reviewQuestions)
        actionItems = container.lenientStrings(.actionItems)
        uncertainties = container.lenientStrings(.uncertainties)
        outline = container.lenientList(LectureOutlineItem.self, .outline)
        glossary = container.lenientList(LectureGlossaryTerm.self, .glossary)
        formulas = container.lenientList(LectureFormula.self, .formulas)
        otherVoices = container.lenientList(LectureVoiceNote.self, .otherVoices)
        deepDives = container.lenientList(LectureDeepDive.self, .deepDives)
        activities = container.lenientList(LectureActivity.self, .activities)
        quiz = container.lenientList(LectureQuizQuestion.self, .quiz)
    }

    public var isEmpty: Bool {
        summary.trimmed.isEmpty
            && keyPoints.allSatisfy { $0.trimmed.isEmpty }
            && outline.isEmpty
            && glossary.isEmpty
    }

    /// Trims, drops blanks, removes duplicates, and bounds every collection so
    /// a talkative or repetitive model cannot produce an unusable note.
    public func normalized() -> LectureStructure {
        LectureStructure(
            title: title.keyboardNormalized.trimmed.bounded(160),
            courseName: courseName.keyboardNormalized.trimmed.bounded(80),
            courseCode: courseCode.keyboardNormalized.trimmed.bounded(24),
            category: category.keyboardNormalized.trimmed.bounded(40),
            summary: summary.keyboardNormalized.trimmed.bounded(1_200),
            topics: LectureStructure.cleanList(topics, limit: 14, length: 90),
            keyPoints: LectureStructure.cleanList(keyPoints, limit: 20, length: 400),
            outline: LectureStructure.cleanOutline(outline),
            glossary: LectureStructure.cleanGlossary(glossary),
            formulas: LectureStructure.cleanFormulas(formulas),
            reviewQuestions: LectureStructure.cleanList(reviewQuestions, limit: 15, length: 300),
            actionItems: LectureStructure.cleanList(actionItems, limit: 15, length: 300),
            uncertainties: LectureStructure.cleanList(uncertainties, limit: 12, length: 300),
            otherVoices: LectureStructure.cleanVoices(otherVoices),
            deepDives: LectureStructure.cleanDeepDives(deepDives),
            activities: LectureStructure.cleanActivities(activities),
            quiz: LectureStructure.cleanQuiz(quiz)
        )
    }

    /// Combines a later chunk's findings into an earlier partial result.
    /// Earlier prose wins for single-value fields; lists accumulate without
    /// duplicates so a long lecture keeps everything it surfaced.
    public func merging(_ other: LectureStructure) -> LectureStructure {
        LectureStructure(
            title: title.trimmed.isEmpty ? other.title : title,
            courseName: courseName.trimmed.isEmpty ? other.courseName : courseName,
            courseCode: courseCode.trimmed.isEmpty ? other.courseCode : courseCode,
            category: category.trimmed.isEmpty ? other.category : category,
            summary: [summary, other.summary].filter { !$0.trimmed.isEmpty }.joined(separator: " "),
            topics: topics + other.topics,
            keyPoints: keyPoints + other.keyPoints,
            outline: outline + other.outline,
            glossary: glossary + other.glossary,
            formulas: formulas + other.formulas,
            reviewQuestions: reviewQuestions + other.reviewQuestions,
            actionItems: actionItems + other.actionItems,
            uncertainties: uncertainties + other.uncertainties,
            otherVoices: otherVoices + other.otherVoices,
            deepDives: deepDives + other.deepDives,
            activities: activities + other.activities,
            quiz: quiz + other.quiz
        ).normalized()
    }

    private static func cleanList(_ values: [String], limit: Int, length: Int) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.keyboardNormalized.trimmed.strippedBullet.bounded(length) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func cleanOutline(_ items: [LectureOutlineItem]) -> [LectureOutlineItem] {
        var seen = Set<String>()
        return items
            .map { LectureOutlineItem(heading: $0.heading.keyboardNormalized.trimmed.strippedBullet.bounded(120), points: cleanList($0.points, limit: 12, length: 400)) }
            .filter { !$0.heading.isEmpty && seen.insert($0.heading.lowercased()).inserted }
            .prefix(16)
            .map { $0 }
    }

    private static func cleanGlossary(_ terms: [LectureGlossaryTerm]) -> [LectureGlossaryTerm] {
        var seen = Set<String>()
        return terms
            .map {
                LectureGlossaryTerm(
                    term: $0.term.keyboardNormalized.trimmed.strippedBullet.bounded(90),
                    shortDefinition: $0.shortDefinition.keyboardNormalized.trimmed.bounded(400),
                    deepExplanation: $0.deepExplanation.keyboardNormalized.trimmed.bounded(2_000),
                    whyItMatters: $0.whyItMatters.keyboardNormalized.trimmed.bounded(600)
                )
            }
            .filter { !$0.term.isEmpty && !$0.shortDefinition.isEmpty && seen.insert($0.term.lowercased()).inserted }
            .prefix(30)
            .map { $0 }
    }

    /// A companion note has to be substantial to be worth the click; a couple
    /// of sentences belongs in the main note.
    private static func cleanDeepDives(_ dives: [LectureDeepDive]) -> [LectureDeepDive] {
        var seen = Set<String>()
        return dives
            .map {
                LectureDeepDive(
                    title: $0.title.keyboardNormalized.trimmed.strippedBullet.bounded(90),
                    section: $0.section.keyboardNormalized.trimmed.strippedBullet.bounded(120),
                    summary: $0.summary.keyboardNormalized.trimmed.bounded(240),
                    markdown: $0.markdown.keyboardNormalized.trimmed.bounded(20_000)
                )
            }
            .filter { !$0.title.isEmpty && $0.markdown.count >= 200 && seen.insert($0.title.lowercased()).inserted }
            .prefix(6)
            .map { $0 }
    }

    /// An activity needs a name to be worth listing; the rest is optional
    /// because the recording often does not settle what came of it.
    private static func cleanActivities(_ activities: [LectureActivity]) -> [LectureActivity] {
        var seen = Set<String>()
        return activities
            .map {
                LectureActivity(
                    title: $0.title.keyboardNormalized.trimmed.strippedBullet.bounded(120),
                    task: $0.task.keyboardNormalized.trimmed.bounded(600),
                    conclusion: $0.conclusion.keyboardNormalized.trimmed.bounded(600),
                    whenLabel: $0.whenLabel.trimmed.bounded(40)
                )
            }
            .filter { !$0.title.isEmpty && seen.insert($0.title.lowercased()).inserted }
            .prefix(8)
            .map { $0 }
    }

    /// A quiz question is useless without an answer, so one without is dropped
    /// rather than shown as an unanswerable prompt.
    private static func cleanQuiz(_ quiz: [LectureQuizQuestion]) -> [LectureQuizQuestion] {
        var seen = Set<String>()
        return quiz
            .map {
                LectureQuizQuestion(
                    question: $0.question.keyboardNormalized.trimmed.strippedBullet.bounded(400),
                    options: cleanList($0.options, limit: 5, length: 200),
                    answer: $0.answer.keyboardNormalized.trimmed.strippedBullet.bounded(600),
                    explanation: $0.explanation.keyboardNormalized.trimmed.bounded(600),
                    source: $0.source.trimmed.lowercased().bounded(20)
                )
            }
            .filter { !$0.question.isEmpty && !$0.answer.isEmpty && seen.insert($0.question.lowercased()).inserted }
            .prefix(10)
            .map { $0 }
    }

    private static func cleanVoices(_ voices: [LectureVoiceNote]) -> [LectureVoiceNote] {
        var seen = Set<String>()
        return voices
            .map {
                LectureVoiceNote(
                    speaker: $0.speaker.keyboardNormalized.trimmed.bounded(60),
                    content: $0.content.keyboardNormalized.trimmed.strippedBullet.bounded(600),
                    kind: $0.kind.trimmed.lowercased().bounded(20),
                    matters: $0.matters.keyboardNormalized.trimmed.bounded(300)
                )
            }
            .filter { !$0.content.isEmpty && seen.insert($0.content.lowercased()).inserted }
            .map { voice in
                // Never let an invented name through; the audio cannot support one.
                let speaker = voice.speaker.isEmpty ? "Someone in the room" : voice.speaker
                return LectureVoiceNote(speaker: speaker, content: voice.content, kind: voice.kind, matters: voice.matters)
            }
            .prefix(20)
            .map { $0 }
    }

    private static func cleanFormulas(_ formulas: [LectureFormula]) -> [LectureFormula] {
        var seen = Set<String>()
        return formulas
            .map {
                LectureFormula(
                    name: $0.name.keyboardNormalized.trimmed.bounded(90),
                    expression: $0.expression.trimmed.bounded(300),
                    meaning: $0.meaning.keyboardNormalized.trimmed.bounded(600)
                )
            }
            .filter { !$0.expression.isEmpty && seen.insert($0.expression.lowercased()).inserted }
            .prefix(20)
            .map { $0 }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Models write typographic characters that are visually identical to the
    /// ones on a keyboard but do not match them in a search. A student who
    /// types "B-tree" must find a note the model wrote as "B\u{2011}tree".
    var keyboardNormalized: String {
        var value = self
        for exotic in ["\u{2010}", "\u{2011}", "\u{2012}"] {
            value = value.replacingOccurrences(of: exotic, with: "-")
        }
        value = value.replacingOccurrences(of: "\u{00AD}", with: "")
        value = value.replacingOccurrences(of: "\u{2019}", with: "'")
        value = value.replacingOccurrences(of: "\u{00A0}", with: " ")
        return value
    }

    func bounded(_ maximum: Int) -> String {
        count <= maximum ? self : String(prefix(max(1, maximum - 1))) + "\u{2026}"
    }

    /// Models often return list items that still carry their own bullet or
    /// numbering. Markdown adds those back, so strip one leading marker.
    var strippedBullet: String {
        let value = trimmed
        for marker in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "\u{2022} "] where value.hasPrefix(marker) {
            return String(value.dropFirst(marker.count)).trimmed
        }
        let digits = value.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = value.dropFirst(digits.count)
            if let separator = rest.first, separator == "." || separator == ")" {
                return String(rest.dropFirst()).trimmed
            }
        }
        return value
    }
}

extension KeyedDecodingContainer {
    /// Decoding that never fails on a model's imperfect JSON: a missing key, a
    /// null, or a wrong type all become the empty default.
    func lenientString(_ key: Key) -> String {
        (try? decodeIfPresent(String.self, forKey: key)) ?? ""
    }

    func lenientStrings(_ key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }

    func lenientList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (try? decodeIfPresent([T].self, forKey: key)) ?? []
    }
}
