import Foundation
import Testing
@testable import AtlasCore

@Suite("Importing text")
@MainActor
struct ImportTests {

    private let passage = """
    Marketing is a social and managerial process by which individuals and organizations obtain
    what they need and want through creating and exchanging value with others. A need is a basic
    requirement; a want is the shape a need takes through culture; a demand is a want backed by
    purchasing power.
    """

    @Test("An import is a lecture that skips transcription")
    func importsAreLectures() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lecture = try store.beginImport(text: passage, title: "Marketing basics", courseHint: "MKTG2201")

        #expect(lecture.isImported)
        #expect(lecture.hasUsableTranscript)
        #expect(lecture.titleGuess == "Marketing basics")
        #expect(lecture.courseHint == "MKTG2201")
        // Nothing downstream needs a special case: it is an ordinary lecture.
        #expect(store.lectures.count == 1)
    }

    @Test("An import has no length, and does not claim 0:00")
    func importsDoNotPretendToBeRecordings() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let lecture = try store.beginImport(text: passage, title: "", courseHint: nil)
        #expect(lecture.durationLabel == "imported")
        #expect(lecture.titleGuess == "Imported notes")
    }

    @Test("Text too short to write notes from is refused with a reason")
    func tooShortIsRefused() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        #expect(throws: AtlasStoreError.self) {
            try store.beginImport(text: "Marketing.", title: "x", courseHint: nil)
        }
    }

    @Test("An import files itself like any other lecture")
    func importsGetFiled() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        _ = try store.createCollection(title: "Marketing", parentID: school)
        _ = try store.createCollection(title: "DS 1800", parentID: school)

        let lecture = try store.beginImport(text: passage, title: "Marketing basics", courseHint: "Marketing")
        let filed = try store.fileLecture(
            lectureID: lecture.id,
            structure: LectureStructure(title: "Marketing basics", summary: "Needs, wants, demands."),
            transcriptionEngine: "Imported",
            modelIdentifier: nil
        )
        #expect(store.collections.first { $0.id == filed.collectionID }?.title == "Marketing")
        #expect(store.document(id: filed.studyDocumentID) != nil)
    }

    @Test("Settings saved before the quiz existed keep the shipped defaults")
    func oldSettingsDoNotLoseNewSections() {
        // What UserDefaults holds from an earlier version: no quiz, no
        // activities, no review passes.
        let legacy = #"{"detail":"standard","includesKeyPoints":true,"includesOutline":true,"includesGlossary":true,"includesFormulas":true,"includesReviewQuestions":true,"includesOtherVoices":true,"includesFollowUps":true,"embedsCompanions":true,"includesRecordingDetails":true}"#
        let restored = NoteFormatPreferences.decoded(legacy)

        #expect(restored.includesQuiz)
        #expect(restored.includesActivities)
        #expect(restored.reviewPasses == 1)
        #expect(restored.includesOutline)
    }

    @Test("Review passes are clamped to something sane")
    func reviewPassesAreClamped() {
        #expect(NoteFormatPreferences(reviewPasses: 9).reviewPasses == 2)
        #expect(NoteFormatPreferences(reviewPasses: -3).reviewPasses == 0)
    }
}
