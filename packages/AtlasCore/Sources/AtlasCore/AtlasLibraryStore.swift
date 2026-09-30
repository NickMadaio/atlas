import Combine
import Foundation
import SwiftData

@MainActor
public final class AtlasLibraryStore: ObservableObject {
    @Published public private(set) var collections: [AtlasCollectionSnapshot] = []
    @Published public private(set) var documents: [AtlasDocumentSnapshot] = []
    @Published public internal(set) var lectures: [AtlasLectureSnapshot] = []
    @Published public internal(set) var attachments: [AtlasAttachmentSnapshot] = []
    /// Standing facts about a course, keyed by the folder that is the course.
    @Published public internal(set) var courseContexts: [AtlasCourseContextSnapshot] = []

    private let container: ModelContainer
    let context: ModelContext

    public init(inMemory: Bool = false) throws {
        let schema = Schema([
            AtlasCollectionRecord.self,
            AtlasDocumentRecord.self,
            AtlasLectureRecord.self,
            AtlasAttachmentRecord.self,
            AtlasCourseContextRecord.self
        ])
        let configuration = ModelConfiguration(
            "AtlasLibrary",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext
        context.autosaveEnabled = true
        try refresh()
    }

    public func bootstrapIfNeeded(seedData: Data) throws {
        let existing = try context.fetchCount(FetchDescriptor<AtlasCollectionRecord>())
        guard existing == 0 else {
            try refresh()
            return
        }

        let seedCollections = try JSONDecoder().decode([SeedCollection].self, from: seedData)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for collection in seedCollections {
            context.insert(
                AtlasCollectionRecord(
                    id: collection.id,
                    title: collection.title,
                    summary: collection.description,
                    icon: collection.icon,
                    accent: collection.accent,
                    sortOrder: collection.order,
                    parentID: collection.parent
                )
            )

            for document in collection.documents {
                let markdown = document.sections.map { section in
                    "## \(section.title)\n\n\(section.markdown)"
                }.joined(separator: "\n\n")
                context.insert(
                    AtlasDocumentRecord(
                        id: document.id,
                        collectionID: collection.id,
                        title: document.title,
                        summary: document.description,
                        category: document.category,
                        updatedAt: formatter.date(from: document.updated) ?? .now,
                        accent: document.accent,
                        bodyMarkdown: markdown
                    )
                )
            }
        }

        try context.save()
        try refresh()
    }

    public func createCollection(
        title: String,
        summary: String = "",
        parentID: String? = nil
    ) throws -> String {
        let cleanTitle = try Validation.nonEmpty(title, field: "Collection title", maximum: 80)
        let cleanSummary = try Validation.bounded(summary, field: "Collection description", maximum: 240)
        if let parentID {
            guard collectionExists(parentID) else { throw AtlasStoreError.collectionNotFound }
            guard depth(of: parentID) + 1 < Self.maximumCollectionDepth else {
                throw AtlasStoreError.collectionTooDeep
            }
        }
        let id = "\(MarkdownSections.slug(cleanTitle))-\(UUID().uuidString.lowercased().prefix(8))"
        let nextOrder = (collections.map(\.sortOrder).max() ?? 0) + 10
        context.insert(
            AtlasCollectionRecord(
                id: id,
                title: cleanTitle,
                summary: cleanSummary,
                sortOrder: nextOrder,
                parentID: parentID
            )
        )
        try context.save()
        try refresh()
        return id
    }

    public func createDocument(
        in collectionID: String,
        title: String,
        summary: String = "",
        category: String = "Notes",
        bodyMarkdown: String = "## Notes\n\nStart writing here.",
        isAgentOnly: Bool = false,
        parentDocumentID: String? = nil
    ) throws -> String {
        guard collections.contains(where: { $0.id == collectionID }) else {
            throw AtlasStoreError.collectionNotFound
        }
        let cleanTitle = try Validation.nonEmpty(title, field: "Document title", maximum: 120)
        let cleanSummary = try Validation.bounded(summary, field: "Document description", maximum: 300)
        let cleanCategory = try Validation.nonEmpty(category, field: "Category", maximum: 40)
        let cleanBody = try Validation.bounded(bodyMarkdown, field: "Document", maximum: 500_000)
        let id = "\(MarkdownSections.slug(cleanTitle))-\(UUID().uuidString.lowercased().prefix(8))"
        context.insert(
            AtlasDocumentRecord(
                id: id,
                collectionID: collectionID,
                title: cleanTitle,
                summary: cleanSummary,
                category: cleanCategory,
                bodyMarkdown: cleanBody,
                isAgentOnly: isAgentOnly,
                parentDocumentID: parentDocumentID
            )
        )
        try context.save()
        try refresh()
        return id
    }

    public func updateDocument(
        id: String,
        title: String,
        summary: String,
        category: String,
        bodyMarkdown: String
    ) throws {
        guard let record = try documentRecord(id: id) else {
            throw AtlasStoreError.documentNotFound
        }
        record.title = try Validation.nonEmpty(title, field: "Document title", maximum: 120)
        record.summary = try Validation.bounded(summary, field: "Document description", maximum: 300)
        record.category = try Validation.nonEmpty(category, field: "Category", maximum: 40)
        record.bodyMarkdown = try Validation.bounded(bodyMarkdown, field: "Document", maximum: 500_000)
        record.updatedAt = .now
        try context.save()
        try refresh()
    }

    public func toggleFavorite(id: String) throws {
        guard let record = try documentRecord(id: id) else {
            throw AtlasStoreError.documentNotFound
        }
        record.isFavorite.toggle()
        try context.save()
        try refresh()
    }

    public func deleteDocument(id: String) throws {
        guard let record = try documentRecord(id: id) else {
            throw AtlasStoreError.documentNotFound
        }
        context.delete(record)
        try context.save()
        try refresh()
    }

    public func document(id: String) -> AtlasDocumentSnapshot? {
        documents.first(where: { $0.id == id })
    }

    /// Everything a person should see in lists, counts, and recents. A
    /// companion note is reached from the note that links to it, so it does
    /// not also sit loose in the list beside it.
    public var visibleDocuments: [AtlasDocumentSnapshot] {
        documents.filter { !$0.isAgentOnly && $0.parentDocumentID == nil }
    }

    /// Notes hanging off one note, assistant-only ones included: the parent is
    /// where you go to see everything a lecture produced.
    public func childDocuments(of documentID: String) -> [AtlasDocumentSnapshot] {
        documents
            .filter { $0.parentDocumentID == documentID }
            .sorted { $0.title < $1.title }
    }

    /// Resolves a `[[Title]]` reference. Case-insensitive, because the link is
    /// written by a model and the title is read by a person.
    public func document(titled title: String) -> AtlasDocumentSnapshot? {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        return documents.first { $0.title.lowercased() == wanted }
    }

    /// Notes a person browses. Assistant-only source files and companion notes
    /// are excluded unless asked for explicitly: a companion is reached from
    /// the note that links to it, so listing it alongside its parent would make
    /// one lecture look like several.
    public func documents(
        in collectionID: String,
        matching query: String = "",
        includingAgentOnly: Bool = false
    ) -> [AtlasDocumentSnapshot] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return documents.filter { document in
            guard document.collectionID == collectionID else { return false }
            guard includingAgentOnly || (!document.isAgentOnly && document.parentDocumentID == nil) else {
                return false
            }
            guard !normalized.isEmpty else { return true }
            return document.title.localizedCaseInsensitiveContains(normalized)
                || document.summary.localizedCaseInsensitiveContains(normalized)
                || document.category.localizedCaseInsensitiveContains(normalized)
                || document.bodyMarkdown.localizedCaseInsensitiveContains(normalized)
        }
    }

    public func searchDocuments(
        matching query: String,
        collectionID: String? = nil,
        limit: Int = 25,
        includingAgentOnly: Bool = true
    ) throws -> [AtlasDocumentSnapshot] {
        let cleanQuery = try Validation.nonEmpty(query, field: "Search query", maximum: 200)
        let safeLimit = min(max(limit, 1), 100)
        return documents.filter { document in
            guard includingAgentOnly || !document.isAgentOnly else { return false }
            let belongsToCollection = collectionID == nil || document.collectionID == collectionID
            return belongsToCollection && (
                document.title.localizedCaseInsensitiveContains(cleanQuery)
                    || document.summary.localizedCaseInsensitiveContains(cleanQuery)
                    || document.category.localizedCaseInsensitiveContains(cleanQuery)
                    || document.bodyMarkdown.localizedCaseInsensitiveContains(cleanQuery)
            )
        }.prefix(safeLimit).map { $0 }
    }

    public func handleAgentRequest(_ request: AtlasAgentRequest) throws -> AtlasAgentResponse {
        guard request.version == AtlasAgentRequest.protocolVersion else {
            throw AtlasAgentProtocolError.unsupportedVersion
        }
        guard UUID(uuidString: request.id) != nil else {
            throw AtlasAgentProtocolError.invalidRequestID
        }

        switch request.operation {
        case .health:
            return AtlasAgentResponse(
                id: request.id,
                payload: AtlasAgentPayload(message: "Atlas is ready.")
            )
        case .listCollections:
            return AtlasAgentResponse(
                id: request.id,
                payload: AtlasAgentPayload(collections: collections)
            )
        case .searchNotes:
            let query = try required(request.arguments.query, named: "query")
            let matches = try searchDocuments(
                matching: query,
                collectionID: request.arguments.collectionID,
                limit: request.arguments.limit ?? 25
            )
            return AtlasAgentResponse(
                id: request.id,
                payload: AtlasAgentPayload(notes: matches)
            )
        case .readNote:
            let noteID = try required(request.arguments.noteID, named: "noteID")
            guard let note = document(id: noteID) else { throw AtlasStoreError.documentNotFound }
            return AtlasAgentResponse(id: request.id, payload: AtlasAgentPayload(note: note))
        case .createNote:
            let collectionID = try required(request.arguments.collectionID, named: "collectionID")
            let title = try required(request.arguments.title, named: "title")
            let noteID = try createDocument(
                in: collectionID,
                title: title,
                summary: request.arguments.summary ?? "",
                category: request.arguments.category ?? "Notes",
                bodyMarkdown: request.arguments.markdown ?? "## Notes\n\nStart writing here."
            )
            return AtlasAgentResponse(id: request.id, payload: AtlasAgentPayload(noteID: noteID))
        case .updateNote:
            let noteID = try required(request.arguments.noteID, named: "noteID")
            guard let current = document(id: noteID) else { throw AtlasStoreError.documentNotFound }
            guard let expectedUpdatedAt = request.arguments.expectedUpdatedAt else {
                throw AtlasAgentProtocolError.missingArgument("expectedUpdatedAt")
            }
            guard abs(current.updatedAt.timeIntervalSince(expectedUpdatedAt)) < 0.001 else {
                throw AtlasAgentProtocolError.updateConflict
            }
            try updateDocument(
                id: noteID,
                title: request.arguments.title ?? current.title,
                summary: request.arguments.summary ?? current.summary,
                category: request.arguments.category ?? current.category,
                bodyMarkdown: request.arguments.markdown ?? current.bodyMarkdown
            )
            return AtlasAgentResponse(id: request.id, payload: AtlasAgentPayload(note: document(id: noteID)))
        case .listLectures:
            let limit = min(max(request.arguments.limit ?? 25, 1), 100)
            let scoped = lectures.filter { lecture in
                request.arguments.collectionID == nil || lecture.collectionID == request.arguments.collectionID
            }
            return AtlasAgentResponse(
                id: request.id,
                payload: AtlasAgentPayload(lectures: scoped.prefix(limit).map(AtlasLectureSummary.init))
            )
        case .readLecture:
            let lectureID = try required(request.arguments.lectureID, named: "lectureID")
            guard let lecture = lecture(id: lectureID) else { throw AtlasStoreError.lectureNotFound }
            return AtlasAgentResponse(id: request.id, payload: AtlasAgentPayload(lecture: lecture))
        }
    }

    private func required(_ value: String?, named name: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AtlasAgentProtocolError.missingArgument(name)
        }
        return value
    }

    private func documentRecord(id: String) throws -> AtlasDocumentRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasDocumentRecord>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func refresh() throws {
        let collectionRecords = try context.fetch(FetchDescriptor<AtlasCollectionRecord>())
        collections = collectionRecords.map {
            AtlasCollectionSnapshot(
                id: $0.id,
                title: $0.title,
                summary: $0.summary,
                icon: $0.icon,
                accent: $0.accent,
                sortOrder: $0.sortOrder,
                parentID: $0.parentID
            )
        }.sorted {
            if $0.sortOrder == $1.sortOrder { return $0.title < $1.title }
            return $0.sortOrder < $1.sortOrder
        }

        let documentRecords = try context.fetch(FetchDescriptor<AtlasDocumentRecord>())
        documents = documentRecords.map {
            AtlasDocumentSnapshot(
                id: $0.id,
                collectionID: $0.collectionID,
                title: $0.title,
                summary: $0.summary,
                category: $0.category,
                updatedAt: $0.updatedAt,
                accent: $0.accent,
                bodyMarkdown: $0.bodyMarkdown,
                isFavorite: $0.isFavorite,
                isAgentOnly: $0.isAgentOnly,
                parentDocumentID: $0.parentDocumentID
            )
        }.sorted { $0.updatedAt > $1.updatedAt }

        try refreshLectures()
        try refreshAttachments()
        try refreshCourseContexts()
    }
}

public enum AtlasStoreError: LocalizedError {
    case collectionNotFound
    case documentNotFound
    case lectureNotFound
    case collectionCycle
    case collectionTooDeep
    case collectionNotEmpty(notes: Int, folders: Int)
    case invalidValue(field: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .collectionNotFound:
            "The selected collection no longer exists."
        case .documentNotFound:
            "The selected document no longer exists."
        case .lectureNotFound:
            "That recording is no longer in Atlas."
        case .collectionCycle:
            "A folder cannot be moved inside itself."
        case .collectionTooDeep:
            "That would nest folders more than \(AtlasLibraryStore.maximumCollectionDepth) deep."
        case let .collectionNotEmpty(notes, folders):
            {
                var contents: [String] = []
                if notes > 0 { contents.append(notes == 1 ? "1 note" : "\(notes) notes") }
                if folders > 0 { contents.append(folders == 1 ? "1 folder" : "\(folders) folders") }
                return "This folder still holds \(contents.joined(separator: " and ")). Move or delete what is inside it first."
            }()
        case let .invalidValue(field, reason):
            "\(field): \(reason)"
        }
    }
}

enum Validation {
    static func nonEmpty(_ value: String, field: String, maximum: Int) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw AtlasStoreError.invalidValue(field: field, reason: "This field is required.")
        }
        return try bounded(clean, field: field, maximum: maximum)
    }

    static func bounded(_ value: String, field: String, maximum: Int) throws -> String {
        guard value.count <= maximum else {
            throw AtlasStoreError.invalidValue(field: field, reason: "Use \(maximum) characters or fewer.")
        }
        return value
    }
}
