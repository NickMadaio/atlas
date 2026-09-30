import Foundation
import Testing
@testable import AtlasCore

@Suite("Course context")
@MainActor
struct CourseContextTests {

    @Test("Nothing saved means no context block, rather than an empty heading")
    func emptyBriefingProducesNothing() {
        #expect(LectureBriefing.none.promptBlock == nil)
        // A course name alone is not something the model can act on.
        #expect(LectureBriefing(coursePath: "School › CS 2100").promptBlock == nil)
    }

    @Test("Saved facts reach the prompt, quoted so they cannot read as instructions")
    func briefingReachesThePrompt() throws {
        let briefing = LectureBriefing(
            coursePath: "School › CS 2100",
            courseBriefing: "Everything is Python 3.\nWe use pytest."
        )
        let block = try #require(briefing.promptBlock)

        #expect(block.contains("School › CS 2100"))
        #expect(block.contains("> Everything is Python 3."))
        #expect(block.contains("> We use pytest."))
    }

    @Test("Reference material is cut on a boundary and says so")
    func referencesAreBounded() throws {
        let long = String(repeating: "syllabus text. ", count: 2_000)
        let briefing = LectureBriefing(
            courseBriefing: "Python only.",
            references: [LectureAttachmentText(name: "Syllabus.pdf", text: long)]
        )
        let block = try #require(briefing.promptBlock)

        #expect(block.contains("Syllabus.pdf"))
        #expect(block.contains("cut for length"))
        #expect(block.count < LectureBriefing.referenceCharacterBudget + 2_000)
    }

    @Test("Context is added to the writing instructions only when there is some")
    func promptsCarryContextWhenPresent() {
        let bare = LecturePrompts.extractionSystem()
        #expect(!bare.contains("WHAT YOU ALREADY KNOW"))

        let informed = LecturePrompts.extractionSystem(
            briefing: LectureBriefing(courseBriefing: "Everything is Python 3.")
        )
        #expect(informed.contains("WHAT YOU ALREADY KNOW"))
        #expect(informed.contains("Everything is Python 3."))
        // The context rules travel with the facts, or the facts carry no weight.
        #expect(informed.contains("outranks the transcript"))
    }

    @Test("An edited instruction file is what actually gets sent")
    func editedSkillsAreUsed() {
        let edited = LectureSkillSet.standard.setting("Only ever write haiku.", for: .noteWriting)
        let prompt = LecturePrompts.extractionSystem(skills: edited)

        #expect(prompt.contains("Only ever write haiku."))
        #expect(!prompt.contains("You take lecture recordings"))
        #expect(edited.isCustomised(.noteWriting))
        #expect(!edited.isCustomised(.filing))
    }

    @Test("Setting a file back to its default stops it being an override")
    func restoringDefaultClearsOverride() {
        let edited = LectureSkillSet.standard.setting("Something else.", for: .filing)
        let restored = edited.setting(LectureSkill.filing.defaultInstructions, for: .filing)

        #expect(restored.overrides.isEmpty)
        #expect(!restored.isCustomised(.filing))
    }

    @Test("Stored instructions survive a round trip, and unknown files are dropped")
    func skillsPersist() {
        let edited = LectureSkillSet.standard.setting("Course context matters most.", for: .context)
        let restored = LectureSkillSet.decoded(edited.encoded)
        #expect(restored.instructions(for: .context) == "Course context matters most.")

        let stale = LectureSkillSet.decoded(#"{"noLongerASkill":"whatever"}"#)
        #expect(stale.overrides.isEmpty)
    }

    // MARK: - Storage

    @Test("Context saves against the folder, and clearing it removes the row")
    func contextIsStoredPerCollection() throws {
        let store = try makeStore()
        let course = try store.createCollection(title: "CS 2100")

        try store.setCourseContext(collectionID: course, briefing: "Everything is Python 3.")
        #expect(store.courseContext(for: course)?.briefing == "Everything is Python 3.")

        try store.setCourseContext(collectionID: course, briefing: "  ")
        #expect(store.courseContext(for: course) == nil)
    }

    @Test("Context on a parent folder applies to every class inside it")
    func contextIsInherited() throws {
        let store = try makeStore()
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "CS 2100", parentID: school)

        try store.setCourseContext(collectionID: school, briefing: "First year, NU London.")
        try store.setCourseContext(collectionID: course, briefing: "Taught entirely in Python 3.")

        let briefing = store.briefing(forCollection: course)
        let block = try #require(briefing.promptBlock)

        #expect(block.contains("School › CS 2100"))
        #expect(block.contains("About School: First year, NU London."))
        #expect(block.contains("Taught entirely in Python 3."))
    }

    @Test("A lecture with no folder yet still picks up its course from the hint")
    func briefingFoundBeforeFiling() throws {
        let store = try makeStore()
        let course = try store.createCollection(title: "CS 2100 Program Design")
        try store.setCourseContext(collectionID: course, briefing: "Python only, never Java.")

        let lecture = try store.beginLecture(courseHint: "CS2100")
        let block = try #require(store.briefing(forLecture: lecture.id).promptBlock)
        #expect(block.contains("Python only, never Java."))
    }

    @Test("A correction on one recording travels with that recording only")
    func lectureContextIsPerRecording() throws {
        let store = try makeStore()
        let first = try store.beginLecture(courseHint: "CS 2100").id
        let second = try store.beginLecture(courseHint: "CS 2100").id

        try store.setLectureContext(lectureID: first, note: "The Java mention was an aside.")

        #expect(store.lecture(id: first)?.hasContextNote == true)
        #expect(store.lecture(id: second)?.hasContextNote == false)
    }

    @Test("Course material is separate from a lecture's own slides")
    func courseMaterialIsScopedToTheFolder() throws {
        let store = try makeStore()
        let course = try store.createCollection(title: "CS 2100")
        let lectureID = try store.beginLecture(courseHint: "CS 2100").id

        try store.addCourseAttachment(
            collectionID: course,
            fileName: "syllabus.pdf",
            displayName: "Syllabus.pdf",
            extractedText: String(repeating: "Week 1: errors and exceptions. ", count: 10),
            byteSize: 2_000,
            extractionNote: nil
        )

        #expect(store.courseAttachments(for: course).count == 1)
        // The lecture's own attachment list must not pick it up.
        #expect(store.attachments(for: lectureID).isEmpty)
        #expect(store.courseMaterialTexts(for: course).count == 1)
    }

    @Test("Deleting a folder takes its context and material with it")
    func deletingAFolderClearsItsContext() throws {
        let store = try makeStore()
        let course = try store.createCollection(title: "Temporary")
        try store.setCourseContext(collectionID: course, briefing: "Notes about nothing.")
        try store.addCourseAttachment(
            collectionID: course,
            fileName: "outline.pdf",
            displayName: "Outline.pdf",
            extractedText: String(repeating: "content ", count: 20),
            byteSize: 100,
            extractionNote: nil
        )

        try store.deleteCollection(id: course)

        #expect(store.courseContext(for: course) == nil)
        #expect(store.courseAttachments(for: course).isEmpty)
    }

    private func makeStore() throws -> AtlasLibraryStore {
        try AtlasLibraryStore(inMemory: true)
    }
}
