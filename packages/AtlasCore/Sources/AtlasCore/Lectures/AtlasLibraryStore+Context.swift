import Foundation
import SwiftData

@MainActor
extension AtlasLibraryStore {
    /// How much standing context one course may hold. Long enough for a real
    /// briefing, short enough that it cannot crowd the transcript out of the
    /// model's context window.
    public nonisolated static let maximumCourseBriefingCharacters = 4_000
    public nonisolated static let maximumLectureContextCharacters = 2_000
    /// Reference material is quoted into every request about the course, so it
    /// gets a tighter budget than a single lecture's slides.
    public nonisolated static let maximumCourseMaterialPerCollection = 200_000

    // MARK: - Course context

    public func courseContext(for collectionID: String) -> AtlasCourseContextSnapshot? {
        courseContexts.first { $0.collectionID == collectionID }
    }

    public func setCourseContext(collectionID: String, briefing: String) throws {
        guard collections.contains(where: { $0.id == collectionID }) else {
            throw AtlasStoreError.collectionNotFound
        }
        let clean = try Validation.bounded(
            briefing.trimmingCharacters(in: .whitespacesAndNewlines),
            field: "Course context",
            maximum: Self.maximumCourseBriefingCharacters
        )

        if let record = try courseContextRecord(for: collectionID) {
            // Clearing the text removes the row rather than leaving an empty
            // one, so "has context" stays a question with one answer.
            if clean.isEmpty {
                context.delete(record)
            } else {
                record.briefing = clean
                record.updatedAt = .now
            }
        } else if !clean.isEmpty {
            context.insert(AtlasCourseContextRecord(collectionID: collectionID, briefing: clean))
        }
        try context.save()
        try refresh()
    }

    /// Context for a recording in particular — usually a correction written
    /// after reading notes that got something wrong.
    public func setLectureContext(lectureID: String, note: String) throws {
        guard let record = try lectureContextRecord(id: lectureID) else {
            throw AtlasStoreError.lectureNotFound
        }
        record.contextNote = try Validation.bounded(
            note.trimmingCharacters(in: .whitespacesAndNewlines),
            field: "Lecture context",
            maximum: Self.maximumLectureContextCharacters
        )
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    // MARK: - Assembling a briefing

    /// Everything Atlas knows about the class a lecture belongs to.
    ///
    /// Context is inherited down the folder tree: what is true of School is
    /// true of every course inside it, and repeating it per course is how it
    /// goes stale. Outer folders come first, so the specific course has the
    /// last word.
    public func briefing(forLecture lectureID: String) -> LectureBriefing {
        guard let lecture = lecture(id: lectureID) else { return .none }
        let collectionID = lecture.collectionID ?? guessedCollectionID(for: lecture)
        return briefing(
            forCollection: collectionID,
            lectureNote: lecture.contextNote
        )
    }

    public func briefing(forCollection collectionID: String?, lectureNote: String = "") -> LectureBriefing {
        guard let collectionID, collections.contains(where: { $0.id == collectionID }) else {
            return LectureBriefing(lectureNote: lectureNote)
        }
        let path = collectionPath(for: collectionID)
        let inherited = path.compactMap { ancestor -> String? in
            guard let saved = courseContext(for: ancestor.id), saved.hasBriefing else { return nil }
            // Named, so a fact inherited from an outer folder is not mistaken
            // for one about this course.
            return path.count > 1 && ancestor.id != collectionID
                ? "About \(ancestor.title): \(saved.briefing)"
                : saved.briefing
        }

        return LectureBriefing(
            coursePath: path.map(\.title).joined(separator: " \u{203A} "),
            courseBriefing: inherited.joined(separator: "\n\n"),
            lectureNote: lectureNote,
            references: courseMaterialTexts(for: collectionID, includingAncestors: true)
        )
    }

    /// Before a lecture is filed it has no folder, so the hint is the only clue
    /// to which course's context should apply. Matching it here means the very
    /// first recording of a class is still written knowing the class.
    private func guessedCollectionID(for lecture: AtlasLectureSnapshot) -> String? {
        let hint = (lecture.courseHint ?? "").trimmed
        guard !hint.isEmpty else { return nil }
        let wanted = LectureClassifier.tokens(hint)
        var best: (id: String, score: Double)?
        for collection in collections {
            let score = LectureClassifier.similarity(
                wanted,
                LectureClassifier.tokens(collection.title).union(LectureClassifier.tokens(collection.summary))
            )
            if score >= LectureClassifier.matchThreshold, score > (best?.score ?? 0) {
                best = (collection.id, score)
            }
        }
        return best?.id
    }

    // MARK: - Course material

    public func courseAttachments(for collectionID: String) -> [AtlasAttachmentSnapshot] {
        attachments.filter { $0.collectionID == collectionID }
    }

    public func courseMaterialTexts(
        for collectionID: String,
        includingAncestors: Bool = false
    ) -> [LectureAttachmentText] {
        let scope = includingAncestors
            ? collectionPath(for: collectionID).map(\.id)
            : [collectionID]
        return attachments
            .filter { attachment in
                guard let owner = attachment.collectionID else { return false }
                return scope.contains(owner)
            }
            .filter(\.hasText)
            .map {
                LectureAttachmentText(
                    name: $0.displayName,
                    text: $0.extractedText,
                    pages: $0.pages,
                    pageNoun: $0.pageNoun
                )
            }
    }

    public func courseMaterialBudgetRemaining(for collectionID: String) -> Int {
        let used = courseAttachments(for: collectionID).reduce(0) { $0 + $1.extractedText.count }
        return max(0, Self.maximumCourseMaterialPerCollection - used)
    }

    @discardableResult
    public func addCourseAttachment(
        collectionID: String,
        fileName: String,
        displayName: String,
        extractedText: String,
        pages: [AttachmentTextExtractor.Page] = [],
        byteSize: Int,
        extractionNote: String?
    ) throws -> AtlasAttachmentSnapshot {
        guard collections.contains(where: { $0.id == collectionID }) else {
            throw AtlasStoreError.collectionNotFound
        }
        let cleanFileName = try Validation.nonEmpty(fileName, field: "Attachment file", maximum: 200)
        let cleanDisplayName = try Validation.nonEmpty(displayName, field: "Attachment name", maximum: 200)

        let budget = courseMaterialBudgetRemaining(for: collectionID)
        var text = extractedText
        var keptPages = pages
        var note = extractionNote
        if text.count > budget {
            text = String(text.prefix(budget))
            var used = 0
            keptPages = pages.prefix { page in
                used += page.text.count + 2
                return used <= budget
            }.map { $0 }
            note = [note, "Only part of this file was kept: this course's material had reached its size limit."]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        let record = AtlasAttachmentRecord(
            lectureID: "",
            collectionID: collectionID,
            fileName: cleanFileName,
            displayName: cleanDisplayName,
            extractedText: text,
            pagesJSON: AttachmentPageCoding.encode(keptPages),
            byteSize: max(0, byteSize),
            extractionNote: note?.isEmpty == true ? nil : note
        )
        context.insert(record)
        try context.save()
        try refresh()

        guard let snapshot = attachments.first(where: { $0.id == record.id }) else {
            throw AtlasStoreError.documentNotFound
        }
        return snapshot
    }

    // MARK: - Filing

    /// The folder tree as the model is shown it, deepest path spelled out so
    /// nesting is a fact rather than something to infer from an id.
    public func placementOptions() -> [LecturePlacementOption] {
        collectionTree().flatMap(\.flattened).map { node in
            LecturePlacementOption(
                id: node.id,
                path: collectionPath(for: node.id).map(\.title).joined(separator: " \u{203A} "),
                summary: node.collection.summary,
                noteCount: noteCount(in: node.id, includingSubcollections: false),
                childCount: childCollections(of: node.id).count
            )
        }
    }

    // MARK: - Internals

    func refreshCourseContexts() throws {
        let records = try context.fetch(FetchDescriptor<AtlasCourseContextRecord>())
        courseContexts = records.map {
            AtlasCourseContextSnapshot(
                id: $0.id,
                collectionID: $0.collectionID,
                briefing: $0.briefing,
                updatedAt: $0.updatedAt
            )
        }
    }

    private func courseContextRecord(for collectionID: String) throws -> AtlasCourseContextRecord? {
        let target = collectionID
        var descriptor = FetchDescriptor<AtlasCourseContextRecord>(
            predicate: #Predicate { $0.collectionID == target }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func lectureContextRecord(id: String) throws -> AtlasLectureRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasLectureRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
