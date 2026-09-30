import Foundation
import Testing
@testable import AtlasCore

@Suite("Choosing a folder")
@MainActor
struct PlacementTests {

    private func options() -> [LecturePlacementOption] {
        [
            LecturePlacementOption(id: "school", path: "School", summary: "", noteCount: 0, childCount: 2),
            LecturePlacementOption(id: "mktg", path: "School › Marketing", summary: "MKTG2201", noteCount: 2, childCount: 0),
            LecturePlacementOption(id: "ds", path: "School › DS 1800", summary: "Data science", noteCount: 4, childCount: 0)
        ]
    }

    @Test("An existing folder the model picked is used")
    func existingFolderIsHonoured() throws {
        let answer = LecturePlacementAnswer(folderID: "mktg", reason: "This is the marketing course.")
        let decision = try #require(LecturePlacementService.decision(from: answer, options: options()))

        #expect(decision.existingCollectionID == "mktg")
        #expect(decision.reason == "This is the marketing course.")
    }

    @Test("A folder id the model invented is refused rather than guessed at")
    func inventedFolderIsRefused() {
        let answer = LecturePlacementAnswer(folderID: "not-a-real-id")
        #expect(LecturePlacementService.decision(from: answer, options: options()) == nil)
    }

    @Test("A new class is nested where the model said, when that folder exists")
    func newFolderNestsUnderNamedParent() throws {
        let answer = LecturePlacementAnswer(newFolderTitle: "CS 2100", newFolderParentID: "school")
        let decision = try #require(LecturePlacementService.decision(from: answer, options: options()))

        #expect(decision.createsCollection)
        #expect(decision.proposedCollectionTitle == "CS 2100")
        #expect(decision.proposedParentID == "school")
    }

    @Test("An invented parent fails the whole answer, rather than filing at the top level")
    func inventedParentIsRefused() {
        let answer = LecturePlacementAnswer(newFolderTitle: "CS 2100", newFolderParentID: "university")
        #expect(LecturePlacementService.decision(from: answer, options: options()) == nil)
    }

    @Test("A new folder named like an existing one uses the existing one")
    func duplicateTitlesAreNotCreated() throws {
        let answer = LecturePlacementAnswer(newFolderTitle: "marketing", newFolderParentID: "school")
        let decision = try #require(LecturePlacementService.decision(from: answer, options: options()))

        #expect(decision.existingCollectionID == "mktg")
        #expect(!decision.createsCollection)
    }

    @Test("A reply with neither a folder nor a name is refused")
    func emptyAnswerIsRefused() {
        #expect(LecturePlacementService.decision(from: LecturePlacementAnswer(), options: options()) == nil)
    }

    @Test("The prompt shows the tree with full paths, so nesting is visible")
    func promptSpellsOutTheTree() {
        let prompt = LecturePlacementService.user(
            structure: LectureStructure(courseCode: "CS2100"),
            hint: "CS 2100",
            options: options()
        )
        #expect(prompt.contains("id: school | School"))
        #expect(prompt.contains("School › Marketing"))
        #expect(prompt.contains("Course code heard: CS2100"))
    }

    // MARK: - Without a model

    @Test("A new class goes beside the other classes, not next to the folder holding them")
    func newCourseIsNestedWithItsSiblings() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        _ = try store.createCollection(title: "Marketing", parentID: school)
        _ = try store.createCollection(title: "DS 1800", parentID: school)

        let lectureID = try store.beginLecture(courseHint: "CS 2100").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [],
            transcriptText: String(repeating: "Exceptions interrupt execution. ", count: 4),
            durationSeconds: 600,
            endedAt: .now
        )

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(title: "Code quality", courseCode: "CS2100", summary: "Errors and exceptions."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        #expect(filed.createdCollection)
        let created = try #require(store.collections.first { $0.id == filed.collectionID })
        #expect(created.parentID == school)
    }

    @Test("With no folder that groups classes, a new one stays at the top level")
    func noContainerMeansNoNesting() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        _ = try store.createCollection(title: "Marketing")

        let lectureID = try store.beginLecture(courseHint: "CS 2100").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [],
            transcriptText: String(repeating: "Exceptions interrupt execution. ", count: 4),
            durationSeconds: 600,
            endedAt: .now
        )
        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(title: "Code quality", courseCode: "CS2100"),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        let created = try #require(store.collections.first { $0.id == filed.collectionID })
        #expect(created.parentID == nil)
    }

    @Test("A folder that holds notes of its own is not treated as a container")
    func containerMustHoldOnlyFolders() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let mixed = try store.createCollection(title: "Everything")
        _ = try store.createCollection(title: "One", parentID: mixed)
        _ = try store.createCollection(title: "Two", parentID: mixed)
        _ = try store.createDocument(in: mixed, title: "A loose note")

        let container = LectureClassifier.courseContainerID(
            in: store.collections,
            noteCountFor: { store.noteCount(in: $0, includingSubcollections: false) }
        )
        #expect(container == nil)
    }

    @Test("The model's choice is used when it is given, checked, and trusted")
    func proposedDecisionIsHonoured() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let marketing = try store.createCollection(title: "Marketing", parentID: school)

        let lectureID = try store.beginLecture(courseHint: "CS 2100").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [],
            transcriptText: String(repeating: "Brand positioning. ", count: 4),
            durationSeconds: 600,
            endedAt: .now
        )

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(title: "Positioning", courseCode: "CS2100"),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            proposedDecision: LectureClassifier.Decision(
                existingCollectionID: marketing,
                proposedCollectionTitle: "School › Marketing",
                proposedCollectionSummary: "",
                confidence: 0.9,
                reason: "The model said so."
            )
        )
        #expect(filed.collectionID == marketing)
        #expect(!filed.createdCollection)
    }

    @Test("A decision naming a folder that has since gone falls back to making one")
    func staleDecisionDoesNotLoseTheLecture() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lectureID = try store.beginLecture(courseHint: "CS 2100").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [],
            transcriptText: String(repeating: "Exceptions interrupt execution. ", count: 4),
            durationSeconds: 600,
            endedAt: .now
        )

        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(title: "Code quality"),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil,
            proposedDecision: LectureClassifier.Decision(
                existingCollectionID: "deleted-folder",
                proposedCollectionTitle: "CS 2100",
                proposedCollectionSummary: "",
                confidence: 0.9,
                reason: "Stale."
            )
        )
        #expect(filed.createdCollection)
        #expect(store.document(id: filed.studyDocumentID) != nil)
    }
}
