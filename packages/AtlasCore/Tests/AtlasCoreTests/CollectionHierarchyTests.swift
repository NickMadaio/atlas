import Foundation
import Testing
@testable import AtlasCore

@Suite("Collection hierarchy")
@MainActor
struct CollectionHierarchyTests {
    @Test("A folder can hold folders, and the tree reports each one's depth")
    func foldersNest() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        let unit = try store.createCollection(title: "Unit 2", parentID: course)

        let tree = store.collectionTree()
        let root = try #require(tree.first { $0.id == school })
        #expect(root.depth == 0)
        #expect(root.children.map(\.id) == [course])
        #expect(root.children.first?.depth == 1)
        #expect(root.children.first?.children.first?.id == unit)
        #expect(root.flattened.map(\.id) == [school, course, unit])

        // Nested folders are not also listed at the top level.
        #expect(!tree.contains { $0.id == course })
    }

    @Test("A folder cannot be moved inside itself or anything it contains")
    func cyclesAreRefused() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        let unit = try store.createCollection(title: "Unit 2", parentID: course)

        #expect(throws: AtlasStoreError.self) { try store.moveCollection(id: school, toParent: school) }
        #expect(throws: AtlasStoreError.self) { try store.moveCollection(id: school, toParent: course) }
        #expect(throws: AtlasStoreError.self) { try store.moveCollection(id: school, toParent: unit) }

        // The tree is untouched by a refused move.
        #expect(store.collectionTree().first?.flattened.count == 3)
    }

    @Test("Moving a folder to the top level and back keeps its own contents")
    func movingKeepsChildren() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        let unit = try store.createCollection(title: "Unit 2", parentID: course)

        try store.moveCollection(id: course, toParent: nil)
        #expect(store.childCollections(of: nil).map(\.id).sorted() == [course, school].sorted())
        #expect(store.descendants(of: course).map(\.id) == [unit])

        try store.moveCollection(id: course, toParent: school)
        #expect(store.collectionPath(for: unit).map(\.title) == ["School", "DS 1800", "Unit 2"])
    }

    @Test("Nesting stops at the depth limit instead of burying folders")
    func depthIsBounded() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        // Fill every allowed level: depths 0 through maximumCollectionDepth - 1.
        var parent: String? = nil
        for level in 0..<AtlasLibraryStore.maximumCollectionDepth {
            parent = try store.createCollection(title: "Level \(level)", parentID: parent)
        }
        let deepest = try #require(parent)
        #expect(store.depth(of: deepest) == AtlasLibraryStore.maximumCollectionDepth - 1)

        #expect(throws: AtlasStoreError.self) {
            _ = try store.createCollection(title: "Too deep", parentID: parent)
        }

        // The same limit applies when dragging an existing folder in.
        let spare = try store.createCollection(title: "Spare")
        #expect(throws: AtlasStoreError.self) {
            try store.moveCollection(id: spare, toParent: deepest)
        }
    }

    @Test("Deleting a folder that still holds things explains what is inside")
    func deletingIsGuarded() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        _ = try store.createDocument(in: course, title: "Week 1")

        #expect(throws: AtlasStoreError.self) { try store.deleteCollection(id: school) }
        #expect(throws: AtlasStoreError.self) { try store.deleteCollection(id: course) }

        let message = AtlasStoreError.collectionNotEmpty(notes: 1, folders: 2).errorDescription ?? ""
        #expect(message.contains("1 note"))
        #expect(message.contains("2 folders"))
    }

    @Test("An empty folder deletes cleanly")
    func emptyFoldersDelete() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let spare = try store.createCollection(title: "Spare")
        try store.deleteCollection(id: spare)
        #expect(!store.collections.contains { $0.id == spare })
    }

    @Test("A parent folder can count the notes filed below it")
    func countsRollUp() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        _ = try store.createDocument(in: school, title: "Timetable")
        _ = try store.createDocument(in: course, title: "Week 1")
        _ = try store.createDocument(in: course, title: "Week 2")

        #expect(store.noteCount(in: school, includingSubcollections: false) == 1)
        #expect(store.noteCount(in: school, includingSubcollections: true) == 3)
    }

    @Test("A folder whose parent no longer exists shows up at the top level")
    func orphansStayReachable() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)
        _ = try store.createDocument(in: school, title: "Timetable")

        // Simulate the parent disappearing underneath the child.
        try store.deleteDocument(id: store.documents(in: school).first!.id)
        try store.moveCollection(id: course, toParent: nil)
        try store.deleteCollection(id: school)
        try store.moveCollection(id: course, toParent: nil)

        #expect(store.collectionTree().contains { $0.id == course })
        #expect(store.collectionPath(for: course).map(\.id) == [course])
    }

    @Test("Lecture filing still works inside a nested class folder")
    func lecturesFileIntoNestedFolders() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800 — Data Science", parentID: school)

        let lectureID = try store.beginLecture(courseHint: "DS 1800").id
        try store.attachTranscript(
            lectureID: lectureID,
            segments: [AtlasLectureSegment(start: 0, end: 30, text: "Indexes.")],
            transcriptText: "Indexes.",
            durationSeconds: 30,
            endedAt: .now
        )
        let filed = try store.fileLecture(
            lectureID: lectureID,
            structure: LectureStructure(courseName: "Data Science", courseCode: "DS1800", summary: "Indexes."),
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: nil
        )

        #expect(filed.collectionID == course)
        #expect(store.collectionPath(for: course).map(\.title) == ["School", "DS 1800 — Data Science"])
    }
}

@Suite("Folder arranging")
@MainActor
struct FolderArrangingTests {
    @Test("A folder can be dropped into a new position among its siblings")
    func reorderingWithinALevel() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let first = try store.createCollection(title: "First")
        let second = try store.createCollection(title: "Second")
        let third = try store.createCollection(title: "Third")
        #expect(store.childCollections(of: nil).map(\.id) == [first, second, third])

        try store.moveCollection(id: third, toParent: nil, atIndex: 0)
        #expect(store.childCollections(of: nil).map(\.id) == [third, first, second])

        try store.moveCollection(id: third, toParent: nil, atIndex: 2)
        #expect(store.childCollections(of: nil).map(\.id) == [first, second, third])
    }

    @Test("Dropping past the end lands at the end rather than failing")
    func outOfRangeIndexesAreClamped() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let first = try store.createCollection(title: "First")
        let second = try store.createCollection(title: "Second")

        try store.moveCollection(id: first, toParent: nil, atIndex: 99)
        #expect(store.childCollections(of: nil).map(\.id) == [second, first])

        try store.moveCollection(id: first, toParent: nil, atIndex: -5)
        #expect(store.childCollections(of: nil).map(\.id) == [first, second])
    }

    @Test("A folder dragged into another folder lands where it was dropped")
    func reorderingAcrossLevels() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let alpha = try store.createCollection(title: "Alpha", parentID: school)
        let beta = try store.createCollection(title: "Beta", parentID: school)
        let loose = try store.createCollection(title: "Loose")

        try store.moveCollection(id: loose, toParent: school, atIndex: 1)
        #expect(store.childCollections(of: school).map(\.id) == [alpha, loose, beta])
        #expect(store.childCollections(of: nil).map(\.id) == [school])
    }

    @Test("Arranging still refuses a drop that would swallow the folder's own parent")
    func reorderingKeepsTheCycleGuard() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let school = try store.createCollection(title: "School")
        let course = try store.createCollection(title: "DS 1800", parentID: school)

        #expect(throws: AtlasStoreError.self) {
            try store.moveCollection(id: school, toParent: course, atIndex: 0)
        }
        #expect(store.childCollections(of: nil).map(\.id) == [school])
    }
}
