import Foundation
import SwiftData

public struct AtlasFiledLecture: Sendable, Equatable {
    public let lectureID: String
    public let collectionID: String
    public let collectionTitle: String
    public let createdCollection: Bool
    public let studyDocumentID: String
    public let depthDocumentID: String
    public let classificationReason: String
    public let confidence: Double
}

@MainActor
extension AtlasLibraryStore {
    // MARK: - Lifecycle

    /// Opens a lecture as soon as recording starts, so the audio file has a
    /// durable owner before a single word is spoken. Atlas names the file
    /// itself — the caller never chooses a path inside Atlas's container.
    @discardableResult
    public func beginLecture(courseHint: String?, fileExtension: String = "caf") throws -> AtlasLectureSnapshot {
        let hint = try Validation.bounded(courseHint ?? "", field: "Course label", maximum: 120)
        let id = UUID().uuidString.lowercased()
        let safeExtension = fileExtension.filter(\.isLetter).lowercased()
        let record = AtlasLectureRecord(
            id: id,
            audioFileName: "\(id).\(safeExtension.isEmpty ? "caf" : safeExtension)",
            courseHint: hint.isEmpty ? nil : hint,
            titleGuess: hint.isEmpty ? "Untitled lecture" : hint
        )
        context.insert(record)
        try context.save()
        try refresh()
        guard let snapshot = lecture(id: id) else { throw AtlasStoreError.lectureNotFound }
        return snapshot
    }

    /// Opens a lecture from text the student already has: a file, a page they
    /// copied, notes someone else took.
    ///
    /// Deliberately the same object as a recording. Everything after
    /// transcription — structuring, review, filing, companions, the quiz — is
    /// about text, so an import is a lecture that skips the first step, and
    /// gets the rest for free rather than through a second pipeline that would
    /// drift out of step with this one.
    @discardableResult
    public func beginImport(
        text: String,
        title: String,
        courseHint: String?
    ) throws -> AtlasLectureSnapshot {
        let body = try Validation.nonEmpty(text, field: "Imported text", maximum: 1_000_000)
        guard body.trimmed.count >= 40 else {
            throw AtlasStoreError.invalidValue(
                field: "Imported text",
                reason: "There is not enough here to write notes from."
            )
        }
        let hint = try Validation.bounded(courseHint ?? "", field: "Course label", maximum: 120)
        let cleanTitle = try Validation.bounded(title, field: "Title", maximum: 120)
        let id = UUID().uuidString.lowercased()

        let record = AtlasLectureRecord(
            id: id,
            durationSeconds: 0,
            // Named for consistency, never written: an import has no audio.
            audioFileName: "\(id).none",
            transcriptText: body,
            stage: .structuring,
            courseHint: hint.isEmpty ? nil : hint,
            isImported: true,
            titleGuess: cleanTitle.isEmpty ? "Imported notes" : cleanTitle
        )
        record.endedAt = .now
        context.insert(record)
        try context.save()
        try refresh()
        guard let snapshot = lecture(id: id) else { throw AtlasStoreError.lectureNotFound }
        return snapshot
    }

    /// Records how long the captured audio turned out to be, the moment
    /// recording stops and before anything else is attempted.
    public func finishRecording(lectureID: String, durationSeconds: Double, endedAt: Date) throws {
        guard let record = try lectureRecord(id: lectureID) else { throw AtlasStoreError.lectureNotFound }
        record.durationSeconds = max(0, durationSeconds)
        record.endedAt = endedAt
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    public func lecture(id: String) -> AtlasLectureSnapshot? {
        lectures.first(where: { $0.id == id })
    }

    public func updateLectureStage(
        id: String,
        stage: AtlasLectureStage,
        failureReason: String? = nil
    ) throws {
        guard let record = try lectureRecord(id: id) else { throw AtlasStoreError.lectureNotFound }
        record.stage = stage
        record.failureReason = failureReason.map { String($0.prefix(400)) }
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    /// Stores the transcript the moment transcription finishes, before any
    /// model runs. Everything after this point can fail without costing the
    /// user the lecture.
    public func attachTranscript(
        lectureID: String,
        segments: [AtlasLectureSegment],
        transcriptText: String,
        durationSeconds: Double,
        endedAt: Date
    ) throws {
        guard let record = try lectureRecord(id: lectureID) else { throw AtlasStoreError.lectureNotFound }
        record.segments = segments
        record.transcriptText = String(transcriptText.prefix(1_000_000))
        record.durationSeconds = max(0, durationSeconds)
        record.endedAt = endedAt
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    /// Replaces the transcript with a corrected one.
    ///
    /// Timecodes are dropped, because edited text no longer lines up with the
    /// spans the recogniser produced and a timecode that points at the wrong
    /// words is worse than none. Re-running note writing then works from the
    /// corrected text.
    public func updateTranscript(lectureID: String, text: String) throws {
        guard let record = try lectureRecord(id: lectureID) else { throw AtlasStoreError.lectureNotFound }
        let clean = try Validation.bounded(text, field: "Transcript", maximum: 1_000_000)
        record.transcriptText = clean
        record.segmentsJSON = "[]"
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    /// Deletes a recording, optionally taking the notes written from it.
    ///
    /// Keeping them is the safe default, but it leaves notes with no recording
    /// behind them — which reads as a second class that was never taught.
    public func deleteLecture(id: String, includingNotes: Bool = false) throws {
        guard let record = try lectureRecord(id: id) else { throw AtlasStoreError.lectureNotFound }
        try deleteAttachments(forLecture: id)

        if includingNotes {
            var doomed = [record.studyDocumentID, record.depthDocumentID].compactMap { $0 }
            if let studyID = record.studyDocumentID {
                doomed += childDocuments(of: studyID).map(\.id)
            }
            for documentID in Set(doomed) where document(id: documentID) != nil {
                try deleteDocument(id: documentID)
            }
        }
        context.delete(record)
        try context.save()
        try refresh()
    }

    // MARK: - Filing

    /// Classifies the lecture, makes sure its class exists, and writes both the
    /// study note and the depth note. Safe to run again: re-filing updates the
    /// documents it created before rather than making duplicates.
    /// `proposedDecision` is the local model's answer when it had one. It is
    /// still checked here, and token matching runs when it is absent — the
    /// model chooses a folder, it never writes one.
    public func fileLecture(
        lectureID: String,
        structure: LectureStructure,
        transcriptionEngine: String,
        modelIdentifier: String?,
        proposedDecision: LectureClassifier.Decision? = nil,
        format: NoteFormatPreferences = .standard
    ) throws -> AtlasFiledLecture {
        guard let record = try lectureRecord(id: lectureID) else { throw AtlasStoreError.lectureNotFound }

        let decision = proposedDecision ?? LectureClassifier.decide(
            structure: structure,
            hint: record.courseHint,
            collections: collections,
            noteCountFor: { noteCount(in: $0, includingSubcollections: false) }
        )

        let collectionID: String
        var createdCollection = false
        if let existing = decision.existingCollectionID, collections.contains(where: { $0.id == existing }) {
            collectionID = existing
        } else {
            // A new class goes beside the student's other classes. Nesting is
            // refused rather than fatal: a folder at the top level is a tidying
            // job, a lost lecture is not.
            let parentID = decision.proposedParentID.flatMap { candidate in
                collections.contains(where: { $0.id == candidate }) ? candidate : nil
            }
            if let parentID,
               let nested = try? createCollection(
                   title: decision.proposedCollectionTitle,
                   summary: decision.proposedCollectionSummary,
                   parentID: parentID
               ) {
                collectionID = nested
            } else {
                collectionID = try createCollection(
                    title: decision.proposedCollectionTitle,
                    summary: decision.proposedCollectionSummary
                )
            }
            createdCollection = true
        }
        let collectionTitle = collections.first(where: { $0.id == collectionID })?.title ?? decision.proposedCollectionTitle
        let accent = collections.first(where: { $0.id == collectionID })?.accent ?? "slate"

        let context = LectureNoteContext(
            lectureID: record.id,
            recordedAt: record.startedAt,
            durationSeconds: record.durationSeconds,
            courseTitle: collectionTitle,
            transcriptionEngine: transcriptionEngine,
            modelIdentifier: modelIdentifier,
            segments: record.segments,
            transcriptText: record.transcriptText,
            attachments: attachmentTexts(for: record.id),
            briefingNote: briefing(forCollection: collectionID, lectureNote: record.contextNote).promptBlock ?? ""
        )

        let studyTitle = LectureNoteBuilder.title(for: structure, context: context)
        let depthTitle = LectureNoteBuilder.depthTitle(for: studyTitle)
        let studyDraft = LectureNoteBuilder.studyNote(structure: structure, context: context, depthTitle: depthTitle, format: format)
        let depthDraft = LectureNoteBuilder.depthNote(structure: structure, context: context, studyTitle: studyTitle)

        let studyID = try upsertDocument(
            existingID: record.studyDocumentID,
            collectionID: collectionID,
            draft: studyDraft,
            accent: accent
        )
        let depthID = try upsertDocument(
            existingID: record.depthDocumentID,
            collectionID: collectionID,
            draft: depthDraft,
            accent: accent,
            isAgentOnly: true,
            parentDocumentID: studyID
        )

        // Companion notes hang off the note that links to them, so they are
        // reached from it rather than sitting loose in the same folder.
        for dive in structure.deepDives {
            let draft = LectureNoteBuilder.deepDiveNote(dive, context: context, parentTitle: studyTitle)
            let existing = childDocuments(of: studyID).first { $0.title == draft.title }?.id
            _ = try upsertDocument(
                existingID: existing,
                collectionID: collectionID,
                draft: draft,
                accent: accent,
                parentDocumentID: studyID
            )
        }

        record.collectionID = collectionID
        record.studyDocumentID = studyID
        record.depthDocumentID = depthID
        record.titleGuess = studyTitle
        record.modelIdentifier = modelIdentifier
        record.stage = modelIdentifier == nil ? .completeWithoutModel : .complete
        record.failureReason = nil
        record.updatedAt = .now
        try self.context.save()
        try refresh()

        return AtlasFiledLecture(
            lectureID: record.id,
            collectionID: collectionID,
            collectionTitle: collectionTitle,
            createdCollection: createdCollection,
            studyDocumentID: studyID,
            depthDocumentID: depthID,
            classificationReason: decision.reason,
            confidence: decision.confidence
        )
    }

    /// Moves a note to another collection — the one-step correction for a
    /// lecture Atlas filed into the wrong class.
    public func moveDocument(id: String, toCollection collectionID: String) throws {
        guard collections.contains(where: { $0.id == collectionID }) else {
            throw AtlasStoreError.collectionNotFound
        }
        guard let record = try documentRecordForLecture(id: id) else {
            throw AtlasStoreError.documentNotFound
        }
        record.collectionID = collectionID
        record.accent = collections.first(where: { $0.id == collectionID })?.accent ?? record.accent
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    /// Moves every note produced by one lecture at once, so a correction never
    /// leaves the study note and its source in different classes.
    public func moveLecture(id: String, toCollection collectionID: String) throws {
        guard let record = try lectureRecord(id: id) else { throw AtlasStoreError.lectureNotFound }
        for documentID in [record.studyDocumentID, record.depthDocumentID].compactMap({ $0 }) {
            if document(id: documentID) != nil {
                try moveDocument(id: documentID, toCollection: collectionID)
            }
        }
        record.collectionID = collectionID
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    /// Source notes written before they were hidden are still ordinary notes in
    /// the library. Move them out of sight once, at launch.
    public func hideExistingLectureSources() throws {
        let sourceCategory = AtlasLectureDocumentRole.depth.categoryName
        var changed = false
        for lecture in lectures {
            guard let depthID = lecture.depthDocumentID,
                  let record = try documentRecordForLecture(id: depthID) else { continue }
            if !record.isAgentOnly {
                record.isAgentOnly = true
                changed = true
            }
            // Written before notes could link to each other; hang it off its
            // study note so the dropdown finds it.
            if record.parentDocumentID == nil, let studyID = lecture.studyDocumentID {
                record.parentDocumentID = studyID
                changed = true
            }
        }
        // A source note whose recording was deleted has no lecture to link it.
        // Hidden and parentless it would be unreachable, so it is matched back
        // to its study note by the title it was given.
        let suffix = " — source & depth"
        for snapshot in documents where snapshot.category == sourceCategory {
            guard let record = try documentRecordForLecture(id: snapshot.id) else { continue }
            if !record.isAgentOnly {
                record.isAgentOnly = true
                changed = true
            }
            guard record.parentDocumentID == nil, snapshot.title.hasSuffix(suffix) else { continue }
            let studyTitle = String(snapshot.title.dropLast(suffix.count))
            guard let parent = document(titled: studyTitle), parent.id != snapshot.id else { continue }
            record.parentDocumentID = parent.id
            changed = true
        }
        guard changed else { return }
        try context.save()
        try refresh()
    }

    /// Attachments that actually yielded readable text. One that did not is
    /// still listed in the interface, but it has nothing to contribute here.
    public func attachmentTexts(for lectureID: String) -> [LectureAttachmentText] {
        attachments(for: lectureID)
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

    // MARK: - Internals

    func refreshLectures() throws {
        let records = try context.fetch(FetchDescriptor<AtlasLectureRecord>())
        lectures = records.map { record in
            AtlasLectureSnapshot(
                id: record.id,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                durationSeconds: record.durationSeconds,
                audioFileName: record.audioFileName,
                transcriptText: record.transcriptText,
                segments: record.segments,
                stage: record.stage,
                failureReason: record.failureReason,
                courseHint: record.courseHint,
                contextNote: record.contextNote,
                isImported: record.isImported,
                titleGuess: record.titleGuess,
                collectionID: record.collectionID,
                studyDocumentID: record.studyDocumentID,
                depthDocumentID: record.depthDocumentID,
                modelIdentifier: record.modelIdentifier,
                updatedAt: record.updatedAt
            )
        }.sorted { $0.startedAt > $1.startedAt }
    }

    private func upsertDocument(
        existingID: String?,
        collectionID: String,
        draft: LectureNoteDraft,
        accent: String,
        isAgentOnly: Bool = false,
        parentDocumentID: String? = nil
    ) throws -> String {
        if let existingID, document(id: existingID) != nil {
            try updateDocument(
                id: existingID,
                title: draft.title,
                summary: draft.summary,
                category: draft.category,
                bodyMarkdown: draft.markdown
            )
            try moveDocument(id: existingID, toCollection: collectionID)
            // Notes written before companions existed get their link now.
            if let record = try documentRecordForLecture(id: existingID),
               record.parentDocumentID != parentDocumentID {
                record.parentDocumentID = parentDocumentID
                try context.save()
                try refresh()
            }
            return existingID
        }

        let id = try createDocument(
            in: collectionID,
            title: draft.title,
            summary: draft.summary,
            category: draft.category,
            bodyMarkdown: draft.markdown,
            isAgentOnly: isAgentOnly,
            parentDocumentID: parentDocumentID
        )
        if let record = try documentRecordForLecture(id: id) {
            record.accent = accent
            try context.save()
            try refresh()
        }
        return id
    }

    private func lectureRecord(id: String) throws -> AtlasLectureRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasLectureRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func documentRecordForLecture(id: String) throws -> AtlasDocumentRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasDocumentRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

extension AtlasLectureRecord {
    var segments: [AtlasLectureSegment] {
        get { AtlasLectureCoding.decodeSegments(segmentsJSON) }
        set { segmentsJSON = AtlasLectureCoding.encodeSegments(newValue) }
    }
}
