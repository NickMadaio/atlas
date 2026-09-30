import Foundation
import Testing
@testable import AtlasCore

@Suite("Lecture capture")
struct LectureTests {
    // MARK: - Reading what a local model actually returned

    @Test("Model JSON survives fences, prose, and reasoning tags")
    func parserRecoversJSON() {
        let raw = """
        <think>The student wants notes. Let me produce them.</think>
        Sure — here are the notes:
        ```json
        {"title": "Gradient descent", "summary": "How the update rule works.",
         "keyPoints": ["The step size controls stability"]}
        ```
        Let me know if you want more.
        """
        let structure = LectureStructureParser.parse(raw)
        #expect(structure?.title == "Gradient descent")
        #expect(structure?.keyPoints == ["The step size controls stability"])
    }

    @Test("A brace inside a definition does not truncate the object")
    func parserRespectsStrings() {
        let raw = #"{"summary": "A set written {a, b} is unordered.", "keyPoints": ["Sets ignore order"]}"#
        let structure = LectureStructureParser.parse(raw)
        #expect(structure?.summary == "A set written {a, b} is unordered.")
        #expect(structure?.keyPoints.count == 1)
    }

    @Test("Snake case keys decode too")
    func parserAcceptsSnakeCase() {
        let raw = #"{"course_code": "DS1800", "key_points": ["Normalize before joining"], "summary": "Cleaning data."}"#
        let structure = LectureStructureParser.parse(raw)
        #expect(structure?.courseCode == "DS1800")
        #expect(structure?.keyPoints == ["Normalize before joining"])
    }

    @Test("Output with no JSON at all is rejected rather than half-read")
    func parserRejectsProse() {
        #expect(LectureStructureParser.parse("I could not read that transcript, sorry.") == nil)
    }

    @Test("Missing and mistyped fields fall back instead of failing the lecture")
    func structureDecodesLeniently() {
        let raw = #"{"summary": "Covered joins.", "keyPoints": "not a list", "glossary": [{"term": "Join"}]}"#
        let structure = LectureStructureParser.parse(raw)
        #expect(structure?.summary == "Covered joins.")
        #expect(structure?.keyPoints.isEmpty == true)
        // A glossary entry with no definition is not useful, so it is dropped.
        #expect(structure?.glossary.isEmpty == true)
    }

    // MARK: - Normalizing and merging

    @Test("Normalization strips model bullets, blanks, and duplicates")
    func normalizationCleansLists() {
        let structure = LectureStructure(
            summary: "  Trailing space.  ",
            keyPoints: ["- First point", "1. First point", "", "   ", "• Second point"]
        ).normalized()

        #expect(structure.summary == "Trailing space.")
        #expect(structure.keyPoints == ["First point", "Second point"])
    }

    @Test("Merging chunks keeps every distinct idea and drops repeats")
    func mergingAccumulates() {
        let first = LectureStructure(
            title: "Week 3",
            summary: "Opened with review.",
            keyPoints: ["Indexes speed up lookups"],
            glossary: [LectureGlossaryTerm(term: "Index", shortDefinition: "A lookup structure.", deepExplanation: "")]
        )
        let second = LectureStructure(
            title: "Later guess",
            summary: "Closed with an example.",
            keyPoints: ["Indexes speed up lookups", "Writes get slower"],
            glossary: [LectureGlossaryTerm(term: "Index", shortDefinition: "Duplicate.", deepExplanation: "")]
        )

        let merged = first.merging(second)
        #expect(merged.title == "Week 3")
        #expect(merged.summary == "Opened with review. Closed with an example.")
        #expect(merged.keyPoints == ["Indexes speed up lookups", "Writes get slower"])
        #expect(merged.glossary.count == 1)
    }

    @Test("Typographic hyphens from the model stay findable by a typed search")
    func normalizationKeepsTextSearchable() {
        let raw = "{\"summary\": \"We covered B\u{2011}trees.\", \"glossary\": [{\"term\": \"B\u{2011}tree\", \"shortDefinition\": \"A balanced tree.\"}]}"
        let structure = try! #require(LectureStructureParser.parse(raw))

        #expect(structure.summary.contains("B-trees"))
        #expect(structure.glossary.first?.term == "B-tree")
    }

    // MARK: - Chunking

    @Test("Chunks split on segment boundaries and keep their time range")
    func chunkerSplitsOnSegments() {
        let segments = (0..<10).map { index in
            AtlasLectureSegment(
                start: Double(index) * 30,
                end: Double(index + 1) * 30,
                text: String(repeating: "word ", count: 40)
            )
        }
        let chunks = TranscriptChunker.chunks(from: segments, maximumCharacters: 600)

        #expect(chunks.count > 1)
        #expect(chunks.first?.startSeconds == 0)
        #expect(chunks.last?.endSeconds == 300)
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        for chunk in chunks {
            #expect(chunk.text.count <= 1_200)
        }
    }

    @Test("A transcript with no timings still chunks and spans the recording")
    func chunkerHandlesPlainText() {
        let text = (0..<400).map { "word\($0)" }.joined(separator: " ")
        let chunks = TranscriptChunker.chunks(fromPlainText: text, totalDuration: 3_600, maximumCharacters: 800)

        #expect(chunks.count > 1)
        #expect(chunks.first?.startSeconds == 0)
        #expect(chunks.last?.endSeconds == 3_600)
    }

    // MARK: - Choosing the class

    @Test("A spoken course code matches the collection that already exists")
    func classifierMatchesCourseCode() {
        let collections = [
            collection(id: "ds", title: "DS 1800 — Data Science", summary: "Intro data science"),
            collection(id: "cs", title: "CS 2101", summary: "Programming")
        ]
        let decision = LectureClassifier.decide(
            structure: LectureStructure(courseName: "Data Science", courseCode: "DS1800"),
            hint: nil,
            collections: collections
        )

        #expect(decision.existingCollectionID == "ds")
        #expect(decision.confidence > 0.9)
    }

    @Test("A course with no existing collection gets one created for it")
    func classifierCreatesCollection() {
        let decision = LectureClassifier.decide(
            structure: LectureStructure(courseName: "Organic Chemistry", courseCode: "CHEM2311"),
            hint: nil,
            collections: [collection(id: "cs", title: "CS 2101", summary: "Programming")]
        )

        #expect(decision.createsCollection)
        #expect(decision.proposedCollectionTitle.contains("CHEM2311"))
    }

    @Test("An unidentified lecture is held, not filed into an unrelated class")
    func classifierHoldsUnknownLectures() {
        let collections = [collection(id: "cs", title: "CS 2101", summary: "Programming")]
        let decision = LectureClassifier.decide(
            structure: LectureStructure(summary: "Something was discussed."),
            hint: nil,
            collections: collections
        )

        #expect(decision.existingCollectionID == nil)
        #expect(decision.proposedCollectionTitle == LectureClassifier.unfiledCollectionTitle)
        #expect(decision.confidence == 0)
    }

    @Test("The holding collection is reused rather than recreated")
    func classifierReusesHoldingCollection() {
        let collections = [collection(id: "held", title: LectureClassifier.unfiledCollectionTitle, summary: "")]
        let decision = LectureClassifier.decide(
            structure: LectureStructure(),
            hint: nil,
            collections: collections
        )

        #expect(decision.existingCollectionID == "held")
    }

    @Test("A label typed before recording outranks the model's guess")
    func classifierPrefersTheUserHint() {
        let collections = [
            collection(id: "ds", title: "DS 1800 — Data Science", summary: ""),
            collection(id: "cs", title: "CS 2101", summary: "")
        ]
        let decision = LectureClassifier.decide(
            structure: LectureStructure(courseName: "Programming", courseCode: "CS2101"),
            hint: "DS 1800 Wednesday",
            collections: collections
        )

        #expect(decision.existingCollectionID == "ds")
    }

    // MARK: - The two notes

    @Test("The study note reads as notes and points at its source file")
    func studyNoteHasStudentSections() {
        let draft = LectureNoteBuilder.studyNote(
            structure: fullStructure(),
            context: noteContext(),
            depthTitle: "Week 3 — source & depth"
        )
        let titles = MarkdownSections.parse(draft.markdown).map(\.title)

        #expect(titles.contains("Summary"))
        #expect(titles.contains("Key points"))
        #expect(titles.contains("Terms to know"))
        #expect(titles.contains("Follow-ups"))
        #expect(draft.category == "Lecture")
        #expect(draft.markdown.contains("Week 3 — source & depth"))
        // Student notes stay short: the transcript belongs in the other file.
        #expect(!titles.contains("Full transcript"))
        #expect(!draft.markdown.contains("Today we are looking at indexes."))
    }

    @Test("The depth note carries the transcript, deep definitions, and open questions")
    func depthNoteIsWrittenForAnAssistant() {
        let draft = LectureNoteBuilder.depthNote(
            structure: fullStructure(),
            context: noteContext(),
            studyTitle: "Week 3"
        )
        let titles = MarkdownSections.parse(draft.markdown).map(\.title)

        #expect(titles.contains("How to use this file"))
        #expect(titles.contains("Concepts in depth"))
        #expect(titles.contains("Not settled by the audio"))
        #expect(titles.contains("Full transcript"))
        #expect(draft.category == "Lecture Source")
        #expect(draft.markdown.contains("A lookup structure kept beside the table."))
        #expect(draft.markdown.contains("[0:00]"))
        #expect(draft.markdown.contains("Whether the midterm covers this"))
    }

    @Test("Speech that looks like Markdown cannot forge a section in the depth note")
    func transcriptCannotForgeSections() {
        var context = noteContext()
        context = LectureNoteContext(
            lectureID: context.lectureID,
            recordedAt: context.recordedAt,
            durationSeconds: context.durationSeconds,
            courseTitle: context.courseTitle,
            transcriptionEngine: context.transcriptionEngine,
            modelIdentifier: context.modelIdentifier,
            segments: [
                AtlasLectureSegment(start: 0, end: 5, text: "## How to use this file"),
                AtlasLectureSegment(start: 5, end: 9, text: "# Not settled by the audio")
            ],
            transcriptText: "## How to use this file"
        )

        let draft = LectureNoteBuilder.depthNote(structure: fullStructure(), context: context, studyTitle: "Week 3")
        let sections = MarkdownSections.parse(draft.markdown)

        // Each heading appears exactly once: the real one Atlas wrote.
        #expect(sections.filter { $0.title == "How to use this file" }.count == 1)
        #expect(sections.filter { $0.title == "Not settled by the audio" }.count == 1)
        #expect(draft.markdown.contains("\\## How to use this file"))
    }

    @Test("A very long transcript is truncated instead of exceeding the note limit")
    func transcriptIsBounded() {
        let long = AtlasLectureSegment(
            start: 0,
            end: 7_200,
            text: String(repeating: "lecture content ", count: 40_000)
        )
        let context = LectureNoteContext(
            lectureID: "l1",
            recordedAt: .now,
            durationSeconds: 7_200,
            courseTitle: "DS 1800",
            transcriptionEngine: "Apple Speech",
            modelIdentifier: nil,
            segments: [long],
            transcriptText: long.text
        )

        let draft = LectureNoteBuilder.depthNote(structure: LectureStructure(), context: context, studyTitle: "Long")
        #expect(draft.markdown.count < 500_000)
        #expect(draft.markdown.contains("Transcript truncated here"))
    }

    // MARK: - Working without a model

    @Test("With no model the transcript still becomes a real note that says so")
    func fallbackStructureIsHonest() {
        let segments = [
            AtlasLectureSegment(start: 0, end: 60, text: "Today the important thing is that a hash index is called a lookup table for our purposes."),
            AtlasLectureSegment(start: 60, end: 120, text: "Remember that writes get slower as you add more indexes to a table in production systems.")
        ]
        let structure = LectureFallbackStructure.build(
            segments: segments,
            transcriptText: segments.map(\.text).joined(separator: " "),
            hint: "DS 1800",
            durationSeconds: 120
        )

        #expect(structure.courseName == "DS 1800")
        #expect(!structure.summary.isEmpty)
        #expect(!structure.keyPoints.isEmpty)
        #expect(!structure.outline.isEmpty)
        #expect(structure.uncertainties.contains { $0.contains("No local model") })
    }

    // MARK: - Only ever talking to this machine

    @Test("A model endpoint that is not on this machine is refused")
    func loopbackGuardRejectsRemoteHosts() {
        #expect(throws: LectureModelError.self) {
            try LoopbackGuard.validate(URL(string: "https://notes.example.com")!)
        }
        #expect(throws: Never.self) {
            try LoopbackGuard.validate(URL(string: "http://127.0.0.1:11434")!)
        }
        #expect(throws: Never.self) {
            try LoopbackGuard.validate(URL(string: "http://localhost:11434")!)
        }
    }

    // MARK: - Structuring across chunks

    @Test("One failing chunk does not cost the rest of the lecture")
    func structuringSurvivesAPartialFailure() async throws {
        let client = StubModelClient(replies: [
            #"{"summary": "First part.", "keyPoints": ["Point one"]}"#,
            "the model fell over",
            #"{"summary": "Third part.", "keyPoints": ["Point three"]}"#
        ])
        let service = LectureStructuringService(client: client)
        let structure = try await service.makeStructure(
            segments: longSegments(count: 3, charactersEach: 900),
            transcriptText: "",
            hint: nil,
            durationSeconds: 900
        )

        #expect(structure.keyPoints.contains("Point one"))
        #expect(structure.keyPoints.contains("Point three"))
    }

    @Test("When no chunk yields anything usable the caller is told, not given an empty note")
    func structuringFailsLoudly() async {
        let client = StubModelClient(replies: ["nope", "still nope"])
        let service = LectureStructuringService(client: client)

        await #expect(throws: LectureModelError.self) {
            _ = try await service.makeStructure(
                segments: longSegments(count: 2, charactersEach: 900),
                transcriptText: "",
                hint: nil,
                durationSeconds: 600
            )
        }
    }

    @Test("A consolidation pass that loses most of the lecture is discarded")
    func structuringKeepsTheRicherResult() async throws {
        let client = StubModelClient(replies: [
            #"{"summary": "A.", "keyPoints": ["One", "Two", "Three"], "glossary": [{"term": "Index", "shortDefinition": "A lookup structure."}]}"#,
            #"{"summary": "B.", "keyPoints": ["Four", "Five"]}"#,
            #"{"summary": "Tiny.", "keyPoints": []}"#
        ])
        let service = LectureStructuringService(client: client)
        let structure = try await service.makeStructure(
            segments: longSegments(count: 2, charactersEach: 900),
            transcriptText: "",
            hint: nil,
            durationSeconds: 600
        )

        #expect(structure.keyPoints.count == 5)
    }

    // MARK: - Helpers

    private func collection(id: String, title: String, summary: String) -> AtlasCollectionSnapshot {
        AtlasCollectionSnapshot(id: id, title: title, summary: summary, icon: "folder", accent: "slate", sortOrder: 10)
    }

    private func noteContext() -> LectureNoteContext {
        LectureNoteContext(
            lectureID: "lecture-1",
            recordedAt: Date(timeIntervalSince1970: 1_757_000_000),
            durationSeconds: 3_120,
            courseTitle: "DS 1800 — Data Science",
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            segments: [
                AtlasLectureSegment(start: 0, end: 30, text: "Today we are looking at indexes."),
                AtlasLectureSegment(start: 30, end: 61, text: "An index is a lookup structure.")
            ],
            transcriptText: "Today we are looking at indexes. An index is a lookup structure."
        )
    }

    private func fullStructure() -> LectureStructure {
        LectureStructure(
            title: "Week 3",
            courseName: "Data Science",
            courseCode: "DS1800",
            category: "Lecture",
            summary: "Indexes, what they cost, and when to add one.",
            topics: ["Indexes", "Query planning"],
            keyPoints: ["Indexes speed up reads", "Every index slows writes"],
            outline: [LectureOutlineItem(heading: "Why indexes exist", points: ["Scanning is linear"])],
            glossary: [
                LectureGlossaryTerm(
                    term: "Index",
                    shortDefinition: "A lookup structure kept beside the table.",
                    deepExplanation: "A B-tree ordered by the indexed column, letting lookups skip most rows.",
                    whyItMatters: "Most query tuning in this course starts here."
                )
            ],
            formulas: [LectureFormula(name: "Lookup cost", expression: "O(log n)", meaning: "Cost of a balanced tree lookup.")],
            reviewQuestions: ["When does an index stop helping?"],
            actionItems: ["Read chapter 4"],
            uncertainties: ["Whether the midterm covers this"]
        )
    }

    private func longSegments(count: Int, charactersEach: Int) -> [AtlasLectureSegment] {
        (0..<count).map { index in
            AtlasLectureSegment(
                start: Double(index) * 300,
                end: Double(index + 1) * 300,
                text: String(repeating: "a", count: charactersEach)
            )
        }
    }
}

/// Returns canned replies in order, so chunk handling can be tested without a
/// model installed.
private struct StubModelClient: LectureModelClient {
    let identifier = "Stub model"
    var chunkCharacterBudget: Int { 1_000 }
    let replies: [String]
    private let cursor = Cursor()

    func isReachable() async -> Bool { true }

    func complete(system: String, user: String) async throws -> String {
        let index = await cursor.next()
        guard index < replies.count else { throw LectureModelError.emptyResponse }
        return replies[index]
    }

    private actor Cursor {
        private var value = 0
        func next() -> Int {
            defer { value += 1 }
            return value
        }
    }
}

@Suite("Room audio")
struct RoomAudioTests {
    private func context() -> LectureNoteContext {
        LectureNoteContext(
            lectureID: "l1",
            recordedAt: Date(timeIntervalSince1970: 1_757_000_000),
            durationSeconds: 600,
            courseTitle: "DS 1800",
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            segments: [AtlasLectureSegment(start: 0, end: 20, text: "Indexes cost writes.")],
            transcriptText: "Indexes cost writes."
        )
    }

    private func structure() -> LectureStructure {
        LectureStructure(
            title: "Indexes",
            summary: "Indexes cost writes.",
            keyPoints: ["Every index slows writes"],
            otherVoices: [
                LectureVoiceNote(
                    speaker: "A student",
                    content: "Does a partial index still slow inserts?",
                    kind: "question",
                    matters: "The lecturer's answer follows in the key points."
                )
            ]
        )
    }

    @Test("Someone else's words are kept but never attributed to the lecturer")
    func otherVoicesAreAttributed() {
        let study = LectureNoteBuilder.studyNote(structure: structure(), context: context(), depthTitle: "d")
        let depth = LectureNoteBuilder.depthNote(structure: structure(), context: context(), studyTitle: "s")

        #expect(MarkdownSections.parse(study.markdown).map(\.title).contains("From the room"))
        #expect(study.markdown.contains("A student"))
        #expect(study.markdown.contains("not by the lecturer"))

        let depthTitles = MarkdownSections.parse(depth.markdown).map(\.title)
        #expect(depthTitles.contains("Other voices in the room"))
        #expect(depth.markdown.contains("None of the following is the lecturer"))
        #expect(depth.markdown.contains("Does a partial index still slow inserts?"))
    }

    @Test("A voice with no named speaker is labelled rather than guessed")
    func anonymousVoicesGetASafeLabel() {
        let raw = #"{"summary":"x","otherVoices":[{"content":"Is that on the exam?","kind":"question"}]}"#
        let parsed = LectureStructureParser.parse(raw)
        #expect(parsed?.otherVoices.first?.speaker == "Someone in the room")
        #expect(parsed?.otherVoices.first?.content == "Is that on the exam?")
    }

    @Test("Empty room chatter is dropped instead of padding the notes")
    func emptyVoicesAreDropped() {
        let raw = #"{"summary":"x","otherVoices":[{"speaker":"A student","content":"   "},{"speaker":"A student","content":"Same question","kind":"question"},{"speaker":"Someone","content":"same question"}]}"#
        let parsed = LectureStructureParser.parse(raw)
        #expect(parsed?.otherVoices.count == 1)
    }

    @Test("A lecture with no other voices shows no room section at all")
    func noRoomSectionWhenSilent() {
        var quiet = structure()
        quiet.otherVoices = []
        let study = LectureNoteBuilder.studyNote(structure: quiet, context: context(), depthTitle: "d")
        #expect(!MarkdownSections.parse(study.markdown).map(\.title).contains("From the room"))
    }
}
