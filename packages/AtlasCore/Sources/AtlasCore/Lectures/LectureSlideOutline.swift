import Foundation

/*
 What the slides say, read before the recording is.

 The two sources are not equal and should not be merged as though they were.
 A deck states the lecture's objectives, its section order, and every technical
 term spelled correctly. A transcript states what was actually said about them,
 badly — "societal marketing concept" arrives as "society of Martin concept",
 "Spotify Wrapped" as "Spotify rap".

 So the deck goes first and becomes the skeleton: the outline the spoken notes
 hang on, and the spelling authority that repairs them. Reading both
 independently and merging the results, which is what happened before, throws
 that away — the pass reading the transcript never learns the right word.
*/
public struct LectureSlideOutline: Codable, Hashable, Sendable {
    public struct Section: Codable, Hashable, Sendable {
        public var heading: String
        public var startsAt: String

        public init(heading: String, startsAt: String = "") {
            self.heading = heading
            self.startsAt = startsAt
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            heading = container.lenientString(.heading)
            startsAt = container.lenientString(.startsAt)
        }
    }

    public struct Term: Codable, Hashable, Sendable {
        public var term: String
        public var definition: String

        public init(term: String, definition: String = "") {
            self.term = term
            self.definition = definition
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            term = container.lenientString(.term)
            definition = container.lenientString(.definition)
        }
    }

    public var title: String
    public var objectives: [String]
    public var sections: [Section]
    public var terms: [Term]
    public var processes: [String]

    public init(
        title: String = "",
        objectives: [String] = [],
        sections: [Section] = [],
        terms: [Term] = [],
        processes: [String] = []
    ) {
        self.title = title
        self.objectives = objectives
        self.sections = sections
        self.terms = terms
        self.processes = processes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenientString(.title)
        objectives = container.lenientStrings(.objectives)
        sections = container.lenientList(Section.self, .sections)
        terms = container.lenientList(Term.self, .terms)
        processes = container.lenientStrings(.processes)
    }

    public var isEmpty: Bool {
        title.trimmed.isEmpty && objectives.isEmpty && sections.isEmpty && terms.isEmpty
    }

    public func normalized() -> LectureSlideOutline {
        var seenSection = Set<String>()
        var seenTerm = Set<String>()
        return LectureSlideOutline(
            title: title.keyboardNormalized.trimmed.bounded(160),
            objectives: LectureSlideOutline.clean(objectives, limit: 12, length: 240),
            sections: sections
                .map { Section(heading: $0.heading.keyboardNormalized.trimmed.strippedBullet.bounded(120), startsAt: $0.startsAt.trimmed.bounded(24)) }
                .filter { !$0.heading.isEmpty && seenSection.insert($0.heading.lowercased()).inserted }
                .prefix(24)
                .map { $0 },
            terms: terms
                .map { Term(term: $0.term.keyboardNormalized.trimmed.strippedBullet.bounded(90), definition: $0.definition.keyboardNormalized.trimmed.bounded(400)) }
                .filter { !$0.term.isEmpty && seenTerm.insert($0.term.lowercased()).inserted }
                .prefix(60)
                .map { $0 },
            processes: LectureSlideOutline.clean(processes, limit: 12, length: 400)
        )
    }

    private static func clean(_ values: [String], limit: Int, length: Int) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.keyboardNormalized.trimmed.strippedBullet.bounded(length) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// The outline as it is put in front of the pass reading the transcript.
    ///
    /// Terms come last and are listed bare, because that is the part doing the
    /// real work: a list of correctly spelled words the model can match a
    /// mis-heard sound against.
    public var promptBlock: String? {
        guard !isEmpty else { return nil }
        var lines: [String] = ["THE SLIDES FOR THIS LECTURE"]
        lines.append("")
        lines.append("Read before the recording. The deck is typed, so it is right where the transcript disagrees. Use its section order as the outline, and its spelling for every technical term.")

        if !title.trimmed.isEmpty {
            lines.append("")
            lines.append("Deck title: \(title.trimmed)")
        }
        if !objectives.isEmpty {
            lines.append("")
            lines.append("What the lecture set out to cover:")
            lines.append(contentsOf: objectives.map { "- \($0)" })
        }
        if !sections.isEmpty {
            lines.append("")
            lines.append("Sections, in the order the deck has them:")
            lines.append(contentsOf: sections.map { section in
                section.startsAt.isEmpty ? "- \(section.heading)" : "- \(section.heading) (\(section.startsAt))"
            })
        }
        if !processes.isEmpty {
            lines.append("")
            lines.append("Processes and formulas the deck writes out:")
            lines.append(contentsOf: processes.map { "- \($0)" })
        }
        if !terms.isEmpty {
            lines.append("")
            lines.append("Terms, spelled as the deck spells them. Where the transcript has something that sounds like one of these, it IS this:")
            lines.append(contentsOf: terms.map { term in
                term.definition.isEmpty ? "- \(term.term)" : "- \(term.term) — \(term.definition)"
            })
        }
        return lines.joined(separator: "\n")
    }
}
