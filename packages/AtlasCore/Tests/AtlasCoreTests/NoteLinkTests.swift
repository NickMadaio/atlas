import Foundation
import Testing
@testable import AtlasCore

@Suite("Links between notes")
struct NoteLinkTests {
    @Test("A wiki link becomes a real Markdown link, round-tripping the title")
    func wikiLinksResolve() {
        let source = "See [[DS 1800 · Selectivity]] for the derivation."
        let resolved = AtlasNoteLinks.resolvingWikiLinks(in: source)

        #expect(resolved.contains("[DS 1800 · Selectivity](atlas-note:"))
        let url = try! #require(URL(string: String(
            resolved.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
        )))
        #expect(AtlasNoteLinks.title(from: url) == "DS 1800 · Selectivity")
    }

    @Test("Ordinary Markdown links are left alone")
    func ordinaryLinksAreUntouched() {
        let source = "Read [the syllabus](https://example.com/syllabus) first."
        #expect(AtlasNoteLinks.resolvingWikiLinks(in: source) == source)
    }

    @Test("Referenced titles come back in order, without repeats")
    func referencedTitlesAreListed() {
        let source = "[[Alpha]] then [[Beta]] then [[alpha]] again."
        #expect(AtlasNoteLinks.referencedTitles(in: source) == ["Alpha", "Beta"])
    }

    @Test("An unterminated or empty link is left as written rather than made dead")
    func brokenLinksAreLeftAlone() {
        #expect(AtlasNoteLinks.resolvingWikiLinks(in: "An [[unclosed reference").contains("[[unclosed"))
        #expect(AtlasNoteLinks.resolvingWikiLinks(in: "Empty [[]] here").contains("[[]]"))
        #expect(AtlasNoteLinks.referencedTitles(in: "Empty [[]] here").isEmpty)
    }

    @Test("A URL from somewhere else is not mistaken for a note link")
    func foreignURLsAreIgnored() {
        #expect(AtlasNoteLinks.title(from: URL(string: "https://example.com")!) == nil)
    }
}

@Suite("Companion notes")
@MainActor
struct CompanionNoteTests {
    private func fileLecture(_ store: AtlasLibraryStore, deepDives: [LectureDeepDive]) throws -> AtlasFiledLecture {
        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [AtlasLectureSegment(start: 0, end: 30, text: "Selectivity decides index use.")],
            transcriptText: "Selectivity decides index use.",
            durationSeconds: 30,
            endedAt: .now
        )
        return try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(
                title: "Week 3",
                courseCode: "DS1800",
                summary: "Indexes.",
                deepDives: deepDives
            ),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )
    }

    private var sampleDive: LectureDeepDive {
        LectureDeepDive(
            title: "Selectivity",
            summary: "Why a low-selectivity index is ignored.",
            markdown: String(repeating: "A full work-through of selectivity and the optimizer. ", count: 10)
        )
    }

    @Test("A companion note is created, linked from the main note, and hangs off it")
    func companionsAreLinked() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [sampleDive])

        let study = try #require(store.document(id: filed.studyDocumentID))
        let children = store.childDocuments(of: filed.studyDocumentID)

        // The source file and the companion both hang off the main note.
        #expect(children.count == 2)
        let companion = try #require(children.first { !$0.isAgentOnly })
        #expect(companion.category == "Deep Dive")
        #expect(companion.title.contains("Selectivity"))

        // The main note references it where the topic comes up.
        #expect(study.bodyMarkdown.contains("## Going deeper"))
        #expect(AtlasNoteLinks.referencedTitles(in: study.bodyMarkdown).contains(companion.title))
        // And the reference resolves to a real note.
        #expect(store.document(titled: companion.title)?.id == companion.id)
        // The companion points back.
        #expect(AtlasNoteLinks.referencedTitles(in: companion.bodyMarkdown).contains(study.title))
    }

    @Test("Companions are reached from their parent, not loose in the folder")
    func companionsAreNotLoose() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [sampleDive])

        let listed = store.documents(in: filed.collectionID)
        #expect(listed.map(\.id) == [filed.studyDocumentID])
        // The count agrees with the list: one note, not four.
        #expect(store.noteCount(in: filed.collectionID, includingSubcollections: false) == 1)
    }

    @Test("Writing notes again updates the companion instead of duplicating it")
    func refilingKeepsOneCompanion() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [sampleDive])
        let lectureID = try #require(store.lectures.first).id

        var improved = sampleDive
        improved.markdown = String(repeating: "A better work-through of selectivity. ", count: 12)
        _ = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(title: "Week 3", courseCode: "DS1800", summary: "Indexes.", deepDives: [improved]),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b"
        )

        #expect(store.childDocuments(of: filed.studyDocumentID).count == 2)
        let companion = try #require(store.childDocuments(of: filed.studyDocumentID).first { !$0.isAgentOnly })
        #expect(companion.bodyMarkdown.contains("A better work-through"))
    }

    @Test("A lecture with nothing worth breaking out gets no companion")
    func nothingIsSplitByDefault() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [])

        let study = try #require(store.document(id: filed.studyDocumentID))
        #expect(!study.bodyMarkdown.contains("## Going deeper"))
        #expect(store.childDocuments(of: filed.studyDocumentID).count == 1)
    }

    @Test("A two-line idea is not promoted to a note of its own")
    func thinDeepDivesAreRejected() {
        let thin = LectureDeepDive(title: "Selectivity", markdown: "It matters.")
        let structure = LectureStructure(summary: "x", deepDives: [thin, sampleDive]).normalized()
        #expect(structure.deepDives.count == 1)
        #expect(structure.deepDives.first?.title == "Selectivity")
    }

    @Test("Deleting a recording can take its notes and companions with it")
    func deletingCanTakeTheNotes() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [sampleDive])
        let lectureID = try #require(store.lectures.first).id
        #expect(store.documents.count == 3)

        try store.deleteLecture(id: lectureID, includingNotes: true)
        #expect(store.documents.isEmpty)
        #expect(store.noteCount(in: filed.collectionID, includingSubcollections: false) == 0)
    }

    @Test("Keeping the notes leaves them behind, which is why it is offered explicitly")
    func deletingCanKeepTheNotes() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let filed = try fileLecture(store, deepDives: [])
        let lectureID = try #require(store.lectures.first).id

        try store.deleteLecture(id: lectureID, includingNotes: false)
        #expect(store.document(id: filed.studyDocumentID) != nil)
        #expect(store.lectures.isEmpty)
    }
}

@Suite("Recovering orphaned source notes")
@MainActor
struct OrphanedSourceNoteTests {
    @Test("A source note whose recording was deleted is reattached to its study note")
    func orphansAreReattached() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "Marketing")
        let study = try store.createDocument(
            in: collection,
            title: "Introduction and Student Expectations",
            category: "Lecture",
            bodyMarkdown: "## Summary\n\nThe lecture opened."
        )
        let orphan = try store.createDocument(
            in: collection,
            title: "Introduction and Student Expectations — source & depth",
            category: "Lecture Source",
            bodyMarkdown: "## Full transcript\n\nWords."
        )

        try store.hideExistingLectureSources()

        // Hidden from browsing, but reachable from the note it belongs to
        // rather than lost entirely.
        #expect(store.document(id: orphan)?.isAgentOnly == true)
        #expect(store.document(id: orphan)?.parentDocumentID == study)
        #expect(store.childDocuments(of: study).map(\.id) == [orphan])
        #expect(store.documents(in: collection).map(\.id) == [study])
        #expect(store.noteCount(in: collection, includingSubcollections: false) == 1)
    }

    @Test("A source note with no matching study note is not attached to something arbitrary")
    func unmatchedOrphansStayUnattached() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collection = try store.createCollection(title: "Marketing")
        let lonely = try store.createDocument(
            in: collection,
            title: "Some Lecture — source & depth",
            category: "Lecture Source",
            bodyMarkdown: "## Full transcript\n\nWords."
        )

        try store.hideExistingLectureSources()
        #expect(store.document(id: lonely)?.parentDocumentID == nil)
    }
}
