import Foundation
import SwiftData

@MainActor
extension AtlasLibraryStore {
    /// Total extracted text one lecture's attachments may contribute. Past
    /// this the note-writing pass would spend longer on handouts than on the
    /// lecture itself.
    public nonisolated static let maximumAttachmentTextPerLecture = 600_000

    public func attachments(for lectureID: String) -> [AtlasAttachmentSnapshot] {
        attachments.filter { $0.lectureID == lectureID && $0.collectionID == nil }
    }

    /// Removes every piece of course material for a folder, used when the
    /// folder goes so nothing is orphaned in the database.
    public func deleteAttachments(forCollection collectionID: String) throws {
        let target: String? = collectionID
        let descriptor = FetchDescriptor<AtlasAttachmentRecord>(predicate: #Predicate { $0.collectionID == target })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records { context.delete(record) }
        try context.save()
        try refresh()
    }

    public func attachmentTextBudgetRemaining(for lectureID: String) -> Int {
        let used = attachments(for: lectureID).reduce(0) { $0 + $1.extractedText.count }
        return max(0, Self.maximumAttachmentTextPerLecture - used)
    }

    @discardableResult
    public func addAttachment(
        lectureID: String,
        fileName: String,
        displayName: String,
        extractedText: String,
        pages: [AttachmentTextExtractor.Page] = [],
        byteSize: Int,
        extractionNote: String?
    ) throws -> AtlasAttachmentSnapshot {
        guard lecture(id: lectureID) != nil else { throw AtlasStoreError.lectureNotFound }
        let cleanFileName = try Validation.nonEmpty(fileName, field: "Attachment file", maximum: 200)
        let cleanDisplayName = try Validation.nonEmpty(displayName, field: "Attachment name", maximum: 200)

        let budget = attachmentTextBudgetRemaining(for: lectureID)
        var text = extractedText
        var keptPages = pages
        var note = extractionNote
        if text.count > budget {
            text = String(text.prefix(budget))
            // Whole pages are dropped rather than one cut in half, so a page
            // citation never points at text that was trimmed away.
            var used = 0
            keptPages = pages.prefix { page in
                used += page.text.count + 2
                return used <= budget
            }.map { $0 }
            note = [note, "Only part of this file was kept: the attachments for this lecture had reached their size limit."]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        let record = AtlasAttachmentRecord(
            lectureID: lectureID,
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

    public func deleteAttachment(id: String) throws {
        let target = id
        var descriptor = FetchDescriptor<AtlasAttachmentRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
        try refresh()
    }

    /// Removes every attachment belonging to a lecture, used when the lecture
    /// itself is deleted so nothing is orphaned in the database.
    public func deleteAttachments(forLecture lectureID: String) throws {
        let target = lectureID
        let descriptor = FetchDescriptor<AtlasAttachmentRecord>(predicate: #Predicate { $0.lectureID == target })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records { context.delete(record) }
        try context.save()
        try refresh()
    }

    func refreshAttachments() throws {
        let records = try context.fetch(FetchDescriptor<AtlasAttachmentRecord>())
        attachments = records.map { record in
            AtlasAttachmentSnapshot(
                id: record.id,
                lectureID: record.lectureID,
                collectionID: record.collectionID,
                fileName: record.fileName,
                displayName: record.displayName,
                extractedText: record.extractedText,
                pages: AttachmentPageCoding.decode(record.pagesJSON),
                byteSize: record.byteSize,
                addedAt: record.addedAt,
                extractionNote: record.extractionNote
            )
        }.sorted { $0.addedAt < $1.addedAt }
    }
}
