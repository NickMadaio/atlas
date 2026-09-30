import Foundation
import Testing
@testable import AtlasCore

@Suite("Lecture filing")
@MainActor
struct LectureStoreTests {
    @Test("A finished lecture becomes a class, a study note, and a source note")
    func filingProducesBothNotes() throws {
        let store = try makeStore()
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "An index is a lookup structure.",
            durationSeconds: 3_120,
            endedAt: .now
        )

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: structure(),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )

        #expect(filed.createsCollectionTitleIsCourse)
        // One note to read, plus a source file kept out of the way.
        #expect(store.documents(in: filed.collectionID).count == 1)
        #expect(store.documents(in: filed.collectionID, includingAgentOnly: true).count == 2)

        let study = store.document(id: filed.studyDocumentID)
        let depth = store.document(id: filed.depthDocumentID)
        #expect(study?.category == "Lecture")
        #expect(depth?.category == "Lecture Source")
        #expect(depth?.bodyMarkdown.contains("An index is a lookup structure.") == true)

        let lecture = store.lecture(id: lectureID)
        #expect(lecture?.stage == .complete)
        #expect(lecture?.collectionID == filed.collectionID)
        #expect(lecture?.modelIdentifier == "Ollama · gpt-oss:20b")
    }

    @Test("The source note is reachable by ordinary search, with no special casing")
    func filedNotesAreSearchable() throws {
        let store = try makeStore()
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "An index is a lookup structure.",
            durationSeconds: 600,
            endedAt: .now
        )
        _ = try store.fileLecture(
            lectureID: lectureID,
            structure: structure(),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )

        let hits = try store.searchDocuments(matching: "B-tree")
        #expect(hits.contains { $0.category == "Lecture Source" })
    }

    @Test("Writing notes again updates the same two notes instead of duplicating them")
    func refilingIsIdempotent() throws {
        let store = try makeStore()
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "An index is a lookup structure.",
            durationSeconds: 600,
            endedAt: .now
        )

        let first = try store.fileLecture(
            lectureID: lectureID,
            structure: structure(),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )
        #expect(store.lecture(id: lectureID)?.stage == .completeWithoutModel)

        var improved = structure()
        improved.summary = "A much better summary written by a real model."
        let second = try store.fileLecture(
            lectureID: lectureID,
            structure: improved,
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )

        #expect(second.studyDocumentID == first.studyDocumentID)
        #expect(second.depthDocumentID == first.depthDocumentID)
        #expect(store.documents.filter { $0.category == "Lecture" }.count == 1)
        #expect(store.document(id: second.studyDocumentID)?.bodyMarkdown.contains("much better summary") == true)
        #expect(store.lecture(id: lectureID)?.stage == .complete)
    }

    @Test("Correcting the class moves the study note and its source together")
    func movingALectureMovesBothNotes() throws {
        let store = try makeStore()
        let target = try store.createCollection(title: "CS 2101", summary: "Programming")
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "An index is a lookup structure.",
            durationSeconds: 600,
            endedAt: .now
        )
        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: structure(),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        try store.moveLecture(id: lectureID, toCollection: target)

        #expect(store.document(id: filed.studyDocumentID)?.collectionID == target)
        #expect(store.document(id: filed.depthDocumentID)?.collectionID == target)
        #expect(store.lecture(id: lectureID)?.collectionID == target)
        #expect(store.documents(in: filed.collectionID).isEmpty)
    }

    @Test("A recording that named no course is held rather than filed into an unrelated class")
    func unidentifiedLecturesAreHeld() throws {
        let store = try makeStore()
        _ = try store.createCollection(title: "CS 2101", summary: "Programming")
        let lectureID = try store.beginLecture(courseHint: nil).id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "Some speech.",
            durationSeconds: 300,
            endedAt: .now
        )

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(summary: "Something was discussed."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        #expect(filed.collectionTitle == LectureClassifier.unfiledCollectionTitle)
    }

    @Test("A stage change records why, so a stalled lecture explains itself")
    func failuresAreRecorded() throws {
        let store = try makeStore()
        let lectureID = try store.beginLecture(courseHint: nil).id
        try store.updateLectureStage(id: lectureID, stage: .failed, failureReason: "Microphone access was denied.")

        #expect(store.lecture(id: lectureID)?.stage == .failed)
        #expect(store.lecture(id: lectureID)?.failureReason == "Microphone access was denied.")
    }

    @Test("An assistant can list lectures and read one in full through the bridge")
    func agentsCanReadLectures() throws {
        let store = try makeStore()
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: segments(),
            transcriptText: "An index is a lookup structure.",
            durationSeconds: 600,
            endedAt: .now
        )
        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: structure(),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )

        let listed = try store.handleAgentRequest(
            AtlasAgentRequest(operation: .listLectures, arguments: .init())
        )
        let summary = try #require(listed.payload?.lectures?.first)
        #expect(summary.id == lectureID)
        #expect(summary.studyDocumentID == filed.studyDocumentID)
        #expect(summary.depthDocumentID == filed.depthDocumentID)
        #expect(summary.transcriptCharacters > 0)

        let read = try store.handleAgentRequest(
            AtlasAgentRequest(operation: .readLecture, arguments: .init(lectureID: lectureID))
        )
        #expect(read.payload?.lecture?.transcriptText == "An index is a lookup structure.")
        #expect(read.payload?.lecture?.segments.count == 2)
    }

    @Test("Reading a lecture that does not exist fails cleanly")
    func agentsCannotReadAMissingLecture() throws {
        let store = try makeStore()
        #expect(throws: AtlasStoreError.self) {
            _ = try store.handleAgentRequest(
                AtlasAgentRequest(operation: .readLecture, arguments: .init(lectureID: "nope"))
            )
        }
    }

    // MARK: - Helpers

    private func makeStore() throws -> AtlasLibraryStore {
        try AtlasLibraryStore(inMemory: true)
    }

    private func segments() -> [AtlasLectureSegment] {
        [
            AtlasLectureSegment(start: 0, end: 30, text: "Today we are looking at indexes."),
            AtlasLectureSegment(start: 30, end: 61, text: "An index is a lookup structure.")
        ]
    }

    private func structure() -> LectureStructure {
        LectureStructure(
            title: "Week 3 — Indexes",
            courseName: "Data Science",
            courseCode: "DS1800",
            category: "Lecture",
            summary: "Indexes, what they cost, and when to add one.",
            keyPoints: ["Indexes speed up reads"],
            glossary: [
                LectureGlossaryTerm(
                    term: "Index",
                    shortDefinition: "A lookup structure kept beside the table.",
                    deepExplanation: "A B-tree ordered by the indexed column.",
                    whyItMatters: "Query tuning starts here."
                )
            ]
        )
    }
}

private extension AtlasFiledLecture {
    /// The first lecture for a course should open that course's collection.
    var createsCollectionTitleIsCourse: Bool {
        createdCollection && collectionTitle.contains("DS 1800")
    }
}

@Suite("Transcript correction")
@MainActor
struct TranscriptCorrectionTests {
    @Test("A corrected transcript replaces the text and the notes rebuilt from it")
    func editingTheTranscript() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [AtlasLectureSegment(start: 0, end: 30, text: "A bullion column is cheap.")],
            transcriptText: "A bullion column is cheap.",
            durationSeconds: 30,
            endedAt: .now
        )

        try store.updateTranscript(lectureID: lectureID, text: "A boolean column is cheap.")
        let lecture = try #require(store.lecture(id: lectureID))
        #expect(lecture.transcriptText == "A boolean column is cheap.")
        // Timecodes cannot survive an edit, so they are cleared rather than
        // left pointing at words that moved.
        #expect(lecture.segments.isEmpty)

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(courseCode: "DS1800", summary: "Columns."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )
        let depth = try #require(store.document(id: filed.depthDocumentID))
        #expect(depth.bodyMarkdown.contains("A boolean column is cheap."))
        #expect(!depth.bodyMarkdown.contains("bullion"))
    }

    @Test("An over-long transcript is refused rather than truncated silently")
    func transcriptIsBounded() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try store.beginLecture(courseHint: nil).id
        #expect(throws: AtlasStoreError.self) {
            try store.updateTranscript(lectureID: lectureID, text: String(repeating: "a", count: 1_000_001))
        }
    }
}

@Suite("Attachments")
@MainActor
struct AttachmentTests {
    private func makeLecture(_ store: AtlasLibraryStore) throws -> String {
        let id = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: id,
            segments: [AtlasLectureSegment(start: 0, end: 30, text: "A bullion column is cheap.")],
            transcriptText: "A bullion column is cheap.",
            durationSeconds: 30,
            endedAt: .now
        )
        return id
    }

    @Test("Attached text reaches the notes and is marked as the written record")
    func attachmentsReachTheNotes() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try makeLecture(store)
        try store.addAttachment(
            lectureID: lectureID,
            fileName: "a.pdf",
            displayName: "Week 3 slides.pdf",
            extractedText: "A boolean column stores true or false and is cheap to index.",
            byteSize: 2_048,
            extractionNote: nil
        )

        #expect(store.attachments(for: lectureID).count == 1)
        #expect(store.attachmentTexts(for: lectureID).first?.name == "Week 3 slides.pdf")

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(courseCode: "DS1800", summary: "Columns."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )
        let depth = try #require(store.document(id: filed.depthDocumentID))
        #expect(MarkdownSections.parse(depth.bodyMarkdown).map(\.title).contains("Attached material"))
        #expect(depth.bodyMarkdown.contains("A boolean column stores true or false"))
        #expect(depth.bodyMarkdown.contains("Week 3 slides.pdf"))

        let study = try #require(store.document(id: filed.studyDocumentID))
        #expect(study.bodyMarkdown.contains("Also written from: Week 3 slides.pdf"))
    }

    @Test("An attachment with no readable text is kept but contributes nothing")
    func unreadableAttachmentsAreHonest() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try makeLecture(store)
        try store.addAttachment(
            lectureID: lectureID,
            fileName: "scan.pdf",
            displayName: "Scanned handout.pdf",
            extractedText: "",
            byteSize: 900_000,
            extractionNote: "This PDF has no selectable text."
        )

        #expect(store.attachments(for: lectureID).count == 1)
        #expect(store.attachments(for: lectureID).first?.hasText == false)
        #expect(store.attachmentTexts(for: lectureID).isEmpty)
    }

    @Test("Attachment text is capped so one long reading cannot swamp a lecture")
    func attachmentTextIsBudgeted() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try makeLecture(store)
        let huge = String(repeating: "a", count: AtlasLibraryStore.maximumAttachmentTextPerLecture + 5_000)

        let stored = try store.addAttachment(
            lectureID: lectureID,
            fileName: "big.txt",
            displayName: "Whole textbook.txt",
            extractedText: huge,
            byteSize: huge.count,
            extractionNote: nil
        )
        #expect(stored.extractedText.count == AtlasLibraryStore.maximumAttachmentTextPerLecture)
        #expect(stored.extractionNote?.contains("size limit") == true)
        #expect(store.attachmentTextBudgetRemaining(for: lectureID) == 0)
    }

    @Test("Deleting a lecture takes its attachments with it")
    func attachmentsAreCleanedUp() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try makeLecture(store)
        try store.addAttachment(
            lectureID: lectureID,
            fileName: "a.txt",
            displayName: "Notes.txt",
            extractedText: "Some readable content that is long enough to count.",
            byteSize: 64,
            extractionNote: nil
        )

        try store.deleteLecture(id: lectureID)
        #expect(store.attachments.isEmpty)
    }

    @Test("An attachment cannot be added to a lecture that does not exist")
    func attachmentsNeedALecture() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        #expect(throws: AtlasStoreError.self) {
            try store.addAttachment(
                lectureID: "nope",
                fileName: "a.txt",
                displayName: "a.txt",
                extractedText: "x",
                byteSize: 1,
                extractionNote: nil
            )
        }
    }
}

@Suite("Hidden source notes")
@MainActor
struct HiddenSourceNoteTests {
    @Test("The source file is out of lists and counts but still reachable by an assistant")
    func sourceNotesAreHiddenFromBrowsing() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [AtlasLectureSegment(start: 0, end: 30, text: "Indexes use B-trees.")],
            transcriptText: "Indexes use B-trees.",
            durationSeconds: 30,
            endedAt: .now
        )
        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(courseCode: "DS1800", summary: "Indexes."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        // Browsing sees one note, not two.
        #expect(store.documents(in: filed.collectionID).map(\.id) == [filed.studyDocumentID])
        #expect(store.visibleDocuments.contains { $0.id == filed.studyDocumentID })
        #expect(!store.visibleDocuments.contains { $0.id == filed.depthDocumentID })

        // The assistant and the agent bridge still reach it.
        #expect(store.documents(in: filed.collectionID, includingAgentOnly: true).count == 2)
        let found = try store.searchDocuments(matching: "B-tree")
        #expect(found.contains { $0.id == filed.depthDocumentID })
        let browsing = try store.searchDocuments(matching: "B-tree", includingAgentOnly: false)
        #expect(!browsing.contains { $0.id == filed.depthDocumentID })
    }

    @Test("Source notes written before they were hidden get hidden at launch")
    func existingSourceNotesAreBackfilled() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "DS 1800")
        let legacy = try store.createDocument(
            in: collection,
            title: "Old lecture — source & depth",
            category: "Lecture Source",
            bodyMarkdown: "## Full transcript\n\nOld text."
        )
        #expect(store.visibleDocuments.contains { $0.id == legacy })

        try store.hideExistingLectureSources()
        #expect(!store.visibleDocuments.contains { $0.id == legacy })
        #expect(store.document(id: legacy)?.isAgentOnly == true)
    }
}
