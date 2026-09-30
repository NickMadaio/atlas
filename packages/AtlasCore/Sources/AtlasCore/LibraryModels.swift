import Foundation
import SwiftData

public struct SeedCollection: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let icon: String
    public let accent: String
    public let order: Int
    public let parent: String?
    public let documents: [SeedDocument]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        accent = try container.decode(String.self, forKey: .accent)
        order = try container.decode(Int.self, forKey: .order)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        documents = try container.decode([SeedDocument].self, forKey: .documents)
    }
}

public struct SeedDocument: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let updated: String
    public let accent: String
    public let sections: [SeedSection]
}

public struct SeedSection: Codable, Sendable {
    public let id: String
    public let title: String
    public let markdown: String
}

@Model
public final class AtlasCollectionRecord {
    @Attribute(.unique) public var id: String
    public var title: String
    public var summary: String
    public var icon: String
    public var accent: String
    public var sortOrder: Int
    /// The collection this one sits inside, or nil at the top level. Optional
    /// so an existing library migrates to a flat tree with no conversion.
    public var parentID: String? = nil

    public init(
        id: String,
        title: String,
        summary: String,
        icon: String = "folder",
        accent: String = "slate",
        sortOrder: Int = 50,
        parentID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.icon = icon
        self.accent = accent
        self.sortOrder = sortOrder
        self.parentID = parentID
    }
}

@Model
public final class AtlasDocumentRecord {
    @Attribute(.unique) public var id: String
    public var collectionID: String
    public var title: String
    public var summary: String
    public var category: String
    public var updatedAt: Date
    public var accent: String
    public var bodyMarkdown: String
    public var isFavorite: Bool
    /// Written for an assistant to read, not for browsing. Kept out of note
    /// lists, search, and counts, while staying a fully ordinary note for the
    /// local assistant and the agent bridge.
    ///
    /// The default lives on the declaration, not only in `init`: SwiftData
    /// migrates an existing store by reading the declared default, and a
    /// non-optional attribute without one fails the migration outright.
    public var isAgentOnly: Bool = false
    /// The note this one sits under. A companion note — a full work-through of
    /// one hard idea — belongs to the note that sent you to it.
    public var parentDocumentID: String? = nil

    public init(
        id: String,
        collectionID: String,
        title: String,
        summary: String,
        category: String,
        updatedAt: Date = .now,
        accent: String = "slate",
        bodyMarkdown: String,
        isFavorite: Bool = false,
        isAgentOnly: Bool = false,
        parentDocumentID: String? = nil
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.summary = summary
        self.category = category
        self.updatedAt = updatedAt
        self.accent = accent
        self.bodyMarkdown = bodyMarkdown
        self.isFavorite = isFavorite
        self.isAgentOnly = isAgentOnly
        self.parentDocumentID = parentDocumentID
    }
}

public struct AtlasCollectionSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let icon: String
    public let accent: String
    public let sortOrder: Int
    public let parentID: String?

    public init(
        id: String,
        title: String,
        summary: String,
        icon: String = "folder",
        accent: String = "slate",
        sortOrder: Int = 50,
        parentID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.icon = icon
        self.accent = accent
        self.sortOrder = sortOrder
        self.parentID = parentID
    }
}

/// One collection plus its place in the tree, ready for a sidebar to render
/// without recomputing depth on every row.
public struct AtlasCollectionNode: Identifiable, Hashable, Sendable {
    public let collection: AtlasCollectionSnapshot
    public let depth: Int
    public let children: [AtlasCollectionNode]

    public var id: String { collection.id }

    public init(collection: AtlasCollectionSnapshot, depth: Int, children: [AtlasCollectionNode]) {
        self.collection = collection
        self.depth = depth
        self.children = children
    }

    /// This node and everything under it, depth-first.
    public var flattened: [AtlasCollectionNode] {
        [self] + children.flatMap(\.flattened)
    }
}

public struct AtlasDocumentSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let collectionID: String
    public let title: String
    public let summary: String
    public let category: String
    public let updatedAt: Date
    public let accent: String
    public let bodyMarkdown: String
    public let isFavorite: Bool
    public let isAgentOnly: Bool
    public let parentDocumentID: String?

    public init(
        id: String,
        collectionID: String,
        title: String,
        summary: String,
        category: String,
        updatedAt: Date,
        accent: String,
        bodyMarkdown: String,
        isFavorite: Bool,
        isAgentOnly: Bool = false,
        parentDocumentID: String? = nil
    ) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.summary = summary
        self.category = category
        self.updatedAt = updatedAt
        self.accent = accent
        self.bodyMarkdown = bodyMarkdown
        self.isFavorite = isFavorite
        self.isAgentOnly = isAgentOnly
        self.parentDocumentID = parentDocumentID
    }
}

public struct AtlasSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let markdown: String
}
