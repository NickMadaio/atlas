import Foundation
import SwiftData

@MainActor
extension AtlasLibraryStore {
    /// What a recovery pass put back.
    public struct LectureRecovery: Sendable, Equatable {
        public let lectureID: String
        public let title: String
        public let hasAudio: Bool
        public let transcriptCharacters: Int
        /// Names the note recorded, for attachments whose rows were lost. The
        /// files themselves are re-registered by the caller, which is the only
        /// part that knows where they live.
        public let attachmentNames: [String]
    }

    /// Rebuilds lecture rows from the source notes that outlived them.
    ///
    /// Idempotent: a lecture that still has a row is skipped, so this is safe
    /// to run at every launch. Nothing is deleted and no note is rewritten —
    /// the worst case is that it finds nothing to do.
    ///
    /// The recovered stage is terminal. A recovered lecture is finished work;
    /// marking it in-progress would put it back through a pipeline it has
    /// already been through.
    @discardableResult
    public func recoverLecturesFromSourceNotes(
        availableAudioFileNames: Set<String> = []
    ) throws -> [LectureRecovery] {
        let sourceCategory = AtlasLectureDocumentRole.depth.categoryName
        let known = Set(lectures.map(\.id))
        var recovered: [LectureRecovery] = []

        for note in documents where note.category == sourceCategory {
            guard let details = LectureSourceNoteReader.details(in: note.bodyMarkdown) else { continue }
            guard !known.contains(details.lectureID) else { continue }
            guard try lectureRecordExists(id: details.lectureID) == false else { continue }

            let transcript = LectureSourceNoteReader.transcript(in: note.bodyMarkdown)
            let audioFileName = "\(details.lectureID).caf"
            let hasAudio = availableAudioFileNames.contains(audioFileName)

            // The study note is the one this hangs off, or the one whose title
            // the details table names.
            let studyID = note.parentDocumentID
                ?? document(titled: details.studyTitle)?.id

            let record = AtlasLectureRecord(
                id: details.lectureID,
                startedAt: details.recordedAt ?? note.updatedAt,
                endedAt: (details.recordedAt ?? note.updatedAt).addingTimeInterval(details.durationSeconds),
                durationSeconds: details.durationSeconds,
                audioFileName: audioFileName,
                transcriptText: transcript.text,
                segmentsJSON: AtlasLectureCoding.encodeSegments(transcript.segments),
                stage: details.modelIdentifier == nil ? .completeWithoutModel : .complete,
                courseHint: details.courseTitle.isEmpty ? nil : details.courseTitle,
                titleGuess: details.studyTitle.isEmpty ? note.title : details.studyTitle,
                collectionID: note.collectionID,
                studyDocumentID: studyID,
                depthDocumentID: note.id,
                modelIdentifier: details.modelIdentifier
            )
            context.insert(record)
            recovered.append(
                LectureRecovery(
                    lectureID: details.lectureID,
                    title: record.titleGuess,
                    hasAudio: hasAudio,
                    transcriptCharacters: transcript.text.count,
                    attachmentNames: details.attachmentNames
                )
            )
        }

        guard !recovered.isEmpty else { return [] }
        try context.save()
        try refresh()
        return recovered
    }

    /// Reattaches companion notes to the note they belong to.
    ///
    /// The link itself is never lost: the companion ends with "Written out from
    /// [[Parent]]" and the parent lists it under Going deeper. So when the
    /// `parentDocumentID` column is wiped — which is what happens when the
    /// store is migrated down to a model that predates it — the relationship
    /// can be read back out of the prose that describes it.
    ///
    /// Only a MUTUAL reference counts. One note mentioning another is a
    /// cross-reference; two notes naming each other is a parent and its
    /// companion. Requiring both is what stops an ordinary link from quietly
    /// filing one note underneath another.
    @discardableResult
    public func relinkCompanionNotes() throws -> Int {
        let byTitle = Dictionary(
            documents.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var relinked = 0

        for note in documents where note.parentDocumentID == nil && !note.isAgentOnly {
            // A study note is never a companion; it is what companions hang off.
            guard note.category != AtlasLectureDocumentRole.study.categoryName else { continue }

            let mentioned = AtlasNoteLinks.referencedTitles(in: note.bodyMarkdown)
            let parent = mentioned.lazy
                .compactMap { byTitle[$0.lowercased()] }
                .first { candidate in
                    guard candidate.id != note.id else { return false }
                    return AtlasNoteLinks.referencedTitles(in: candidate.bodyMarkdown)
                        .contains { $0.caseInsensitiveCompare(note.title) == .orderedSame }
                }

            guard let parent, let record = try documentRecord(forRelink: note.id) else { continue }
            record.parentDocumentID = parent.id
            relinked += 1
        }

        guard relinked > 0 else { return 0 }
        try context.save()
        try refresh()
        return relinked
    }

    private func documentRecord(forRelink id: String) throws -> AtlasDocumentRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasDocumentRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func lectureRecordExists(id: String) throws -> Bool {
        let target = id
        var descriptor = FetchDescriptor<AtlasLectureRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first != nil
    }
}
