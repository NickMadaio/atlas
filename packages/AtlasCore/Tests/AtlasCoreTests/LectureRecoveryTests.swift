import Foundation
import Testing
@testable import AtlasCore

@Suite("Recovering a lecture from its notes")
@MainActor
struct LectureRecoveryTests {

    /// A source note in exactly the shape the builder writes.
    private func sourceNote(lectureID: String, studyTitle: String) -> String {
        """
        ## How to use this file

        This is the complete record of one recorded lecture.

        ## Lecture details

        | Field | Value |
        | --- | --- |
        | Course | CS 2100 |
        | Recorded | Wednesday, Sep 16, 2026 at 11:02 AM |
        | Length | 1:29:30 |
        | Transcription | Apple Speech (on device) |
        | Notes written by | Ollama · gpt-oss:20b |
        | Student note | \(studyTitle) |
        | Attached material | Session 1-2.pptx, Syllabus.docx |
        | Lecture ID | `\(lectureID)` |

        ## Full transcript

        **[0:00]** Right, so today we're looking at code quality.

        **[0:06]** There are two main kinds of errors.

        **[1:30]** Syntax errors and exceptions.
        """
    }

    @Test("The details table reads back exactly")
    func detailsAreParsed() throws {
        let details = try #require(
            LectureSourceNoteReader.details(in: sourceNote(lectureID: "abc-123", studyTitle: "Code quality"))
        )
        #expect(details.lectureID == "abc-123")
        #expect(details.courseTitle == "CS 2100")
        #expect(details.durationSeconds == 5_370)
        #expect(details.modelIdentifier == "Ollama · gpt-oss:20b")
        #expect(details.studyTitle == "Code quality")
        #expect(details.attachmentNames == ["Session 1-2.pptx", "Syllabus.docx"])
        #expect(details.recordedAt != nil)
    }

    @Test("Timecodes come back as segments, each ending where the next begins")
    func transcriptIsRebuilt() {
        let result = LectureSourceNoteReader.transcript(in: sourceNote(lectureID: "abc-123", studyTitle: "Code quality"))
        #expect(result.segments.count == 3)
        #expect(result.segments[0].start == 0)
        #expect(result.segments[0].end == 6)
        #expect(result.segments[2].start == 90)
        #expect(result.text.contains("code quality"))
        #expect(result.text.contains("Syntax errors"))
    }

    @Test("A note with no lecture id is left alone")
    func noIdMeansNoRecovery() {
        #expect(LectureSourceNoteReader.details(in: "## Lecture details\n\nNothing useful here.") == nil)
    }

    @Test("A transcript written without timing is still recovered")
    func untimedTranscriptSurvives() {
        let note = """
        ## Lecture details

        | Field | Value |
        | --- | --- |
        | Lecture ID | `x-1` |

        ## Full transcript

        An index is a lookup structure that speeds up reads.
        """
        let result = LectureSourceNoteReader.transcript(in: note)
        #expect(result.segments.isEmpty)
        #expect(result.text == "An index is a lookup structure that speeds up reads.")
    }

    @Test("A lost lecture is rebuilt, linked to both its notes and its audio")
    func lectureIsRecovered() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "CS 2100")
        let lectureID = "a3c30414-cdc6-467a-934f-7df941dbeaba"

        let studyID = try store.createDocument(
            in: collection,
            title: "Code quality",
            category: "Lecture",
            bodyMarkdown: "## Summary\n\nErrors and exceptions."
        )
        _ = try store.createDocument(
            in: collection,
            title: "Code quality — source & depth",
            category: "Lecture Source",
            bodyMarkdown: sourceNote(lectureID: lectureID, studyTitle: "Code quality"),
            isAgentOnly: true,
            parentDocumentID: studyID
        )

        #expect(store.lectures.isEmpty)

        let recovered = try store.recoverLecturesFromSourceNotes(
            availableAudioFileNames: ["\(lectureID).caf"]
        )

        #expect(recovered.count == 1)
        #expect(recovered[0].hasAudio)
        #expect(recovered[0].attachmentNames == ["Session 1-2.pptx", "Syllabus.docx"])

        let lecture = try #require(store.lecture(id: lectureID))
        #expect(lecture.studyDocumentID == studyID)
        #expect(lecture.durationSeconds == 5_370)
        #expect(lecture.stage == .complete)
        #expect(lecture.collectionID == collection)
        #expect(lecture.hasUsableTranscript)
        #expect(lecture.segments.count == 3)
    }

    @Test("Running it twice changes nothing the second time")
    func recoveryIsIdempotent() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "CS 2100")
        _ = try store.createDocument(
            in: collection,
            title: "Code quality — source & depth",
            category: "Lecture Source",
            bodyMarkdown: sourceNote(lectureID: "abc-123", studyTitle: "Code quality"),
            isAgentOnly: true
        )

        #expect(try store.recoverLecturesFromSourceNotes().count == 1)
        #expect(try store.recoverLecturesFromSourceNotes().isEmpty)
        #expect(store.lectures.count == 1)
    }

    @Test("A lecture that still has its row is never touched")
    func existingLecturesAreLeftAlone() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "CS 2100")
        let lectureID = try store.beginLecture(courseHint: "CS 2100").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [],
            transcriptText: "The real transcript, still here.",
            durationSeconds: 60,
            endedAt: .now
        )
        _ = try store.createDocument(
            in: collection,
            title: "Code quality — source & depth",
            category: "Lecture Source",
            bodyMarkdown: sourceNote(lectureID: lectureID, studyTitle: "Code quality"),
            isAgentOnly: true
        )

        #expect(try store.recoverLecturesFromSourceNotes().isEmpty)
        #expect(store.lecture(id: lectureID)?.transcriptText == "The real transcript, still here.")
        #expect(store.lecture(id: lectureID)?.durationSeconds == 60)
    }

    @Test("Notes with no recording behind them are recovered without audio, not skipped")
    func missingAudioIsStillWorthRecovering() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "CS 2100")
        _ = try store.createDocument(
            in: collection,
            title: "Code quality — source & depth",
            category: "Lecture Source",
            bodyMarkdown: sourceNote(lectureID: "gone-1", studyTitle: "Code quality"),
            isAgentOnly: true
        )

        let recovered = try store.recoverLecturesFromSourceNotes(availableAudioFileNames: [])
        #expect(recovered.count == 1)
        #expect(!recovered[0].hasAudio)
        // The transcript is what rewriting needs, and it survived.
        #expect(store.lecture(id: "gone-1")?.hasUsableTranscript == true)
    }
}

@Suite("Relinking companion notes")
@MainActor
struct CompanionRelinkTests {

    private func library() throws -> (store: AtlasLibraryStore, collection: String) {
        let store = try AtlasLibraryStore(inMemory: true)
        return (store, try store.createCollection(title: "CS 2100"))
    }

    @Test("A companion and its parent naming each other are reattached")
    func mutualReferencesRelink() throws {
        let (store, collection) = try library()
        let studyID = try store.createDocument(
            in: collection,
            title: "Effective Commenting Practices",
            category: "Lecture",
            bodyMarkdown: "## Going deeper\n\n- [[CS 2100 · Context Managers]] — how `with` works."
        )
        _ = try store.createDocument(
            in: collection,
            title: "CS 2100 · Context Managers",
            category: "Deep Dive",
            bodyMarkdown: "## Where this came from\n\nWritten out from [[Effective Commenting Practices]]."
        )

        #expect(store.visibleDocuments.count == 2)
        #expect(try store.relinkCompanionNotes() == 1)

        #expect(store.childDocuments(of: studyID).count == 1)
        // Which is the whole point: one lecture stops looking like two notes.
        #expect(store.visibleDocuments.count == 1)
    }

    @Test("A one-way mention is a cross-reference, not a parent")
    func oneWayLinksAreLeftAlone() throws {
        let (store, collection) = try library()
        _ = try store.createDocument(
            in: collection,
            title: "Reading list",
            category: "Notes",
            bodyMarkdown: "See [[Effective Commenting Practices]] for context."
        )
        _ = try store.createDocument(
            in: collection,
            title: "Effective Commenting Practices",
            category: "Lecture",
            bodyMarkdown: "## Summary\n\nComments explain intent."
        )

        #expect(try store.relinkCompanionNotes() == 0)
        #expect(store.visibleDocuments.count == 2)
    }

    @Test("A study note is never filed underneath another note")
    func studyNotesAreNeverCompanions() throws {
        let (store, collection) = try library()
        _ = try store.createDocument(
            in: collection,
            title: "Lecture one",
            category: "Lecture",
            bodyMarkdown: "Continued in [[Lecture two]]."
        )
        _ = try store.createDocument(
            in: collection,
            title: "Lecture two",
            category: "Lecture",
            bodyMarkdown: "Follows on from [[Lecture one]]."
        )

        // Mutual, but both are lectures in their own right.
        #expect(try store.relinkCompanionNotes() == 0)
        #expect(store.visibleDocuments.count == 2)
    }

    @Test("Running it twice changes nothing the second time")
    func relinkingIsIdempotent() throws {
        let (store, collection) = try library()
        _ = try store.createDocument(
            in: collection,
            title: "Parent",
            category: "Lecture",
            bodyMarkdown: "- [[Child]]"
        )
        _ = try store.createDocument(
            in: collection,
            title: "Child",
            category: "Deep Dive",
            bodyMarkdown: "From [[Parent]]."
        )

        #expect(try store.relinkCompanionNotes() == 1)
        #expect(try store.relinkCompanionNotes() == 0)
    }

    @Test("A note that references one that no longer exists is left where it is")
    func brokenLinksAreSafe() throws {
        let (store, collection) = try library()
        _ = try store.createDocument(
            in: collection,
            title: "CS 2100 · Orphan",
            category: "Deep Dive",
            bodyMarkdown: "Written out from [[A lecture that was deleted]]."
        )
        #expect(try store.relinkCompanionNotes() == 0)
        #expect(store.visibleDocuments.count == 1)
    }
}
