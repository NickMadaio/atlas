import Foundation
import SwiftData

extension AtlasLibraryStore {
    /// How deep collections may nest. Deep enough for course → unit → week,
    /// shallow enough that the sidebar stays readable. Nonisolated so error
    /// messages can name the limit.
    public nonisolated static let maximumCollectionDepth = 6
}

@MainActor
extension AtlasLibraryStore {

    // MARK: - Reading the tree

    public var rootCollections: [AtlasCollectionSnapshot] {
        collections.filter { $0.parentID == nil || !collectionExists($0.parentID) }
    }

    public func childCollections(of parentID: String?) -> [AtlasCollectionSnapshot] {
        collections.filter { collection in
            guard let parentID else {
                return collection.parentID == nil || !collectionExists(collection.parentID)
            }
            return collection.parentID == parentID
        }
    }

    /// The whole hierarchy, ordered the way the sidebar shows it.
    public func collectionTree() -> [AtlasCollectionNode] {
        buildNodes(parentID: nil, depth: 0, visited: [])
    }

    /// Everything nested under a collection, at any depth.
    public func descendants(of collectionID: String) -> [AtlasCollectionSnapshot] {
        var found: [AtlasCollectionSnapshot] = []
        var frontier = [collectionID]
        var seen: Set<String> = [collectionID]

        while let current = frontier.popLast() {
            for child in collections where child.parentID == current {
                guard seen.insert(child.id).inserted else { continue }
                found.append(child)
                frontier.append(child.id)
            }
        }
        return found
    }

    /// Root-to-collection trail, for breadcrumbs and move menus.
    public func collectionPath(for collectionID: String) -> [AtlasCollectionSnapshot] {
        var path: [AtlasCollectionSnapshot] = []
        var seen = Set<String>()
        var current = collections.first(where: { $0.id == collectionID })

        while let collection = current, seen.insert(collection.id).inserted {
            path.insert(collection, at: 0)
            guard let parentID = collection.parentID else { break }
            current = collections.first(where: { $0.id == parentID })
        }
        return path
    }

    public func depth(of collectionID: String) -> Int {
        max(0, collectionPath(for: collectionID).count - 1)
    }

    /// Counts only what a person can actually see. Assistant-only source files
    /// are hidden from every list, so counting them makes the sidebar disagree
    /// with the notes underneath it.
    public func noteCount(in collectionID: String, includingSubcollections: Bool) -> Int {
        let direct = visibleDocuments.count { $0.collectionID == collectionID }
        guard includingSubcollections else { return direct }
        return direct + descendants(of: collectionID).reduce(0) { total, child in
            total + visibleDocuments.count { $0.collectionID == child.id }
        }
    }

    // MARK: - Changing the tree

    public func renameCollection(id: String, title: String, summary: String) throws {
        guard let record = try collectionRecord(id: id) else { throw AtlasStoreError.collectionNotFound }
        record.title = try Validation.nonEmpty(title, field: "Collection name", maximum: 80)
        record.summary = try Validation.bounded(summary, field: "Collection description", maximum: 240)
        try context.save()
        try refresh()
    }

    /// Re-parents a collection. Refuses the two moves that would corrupt the
    /// tree — into itself or into something it already contains — and the one
    /// that would bury it too deep to use.
    public func moveCollection(id: String, toParent parentID: String?) throws {
        guard let record = try collectionRecord(id: id) else { throw AtlasStoreError.collectionNotFound }

        if let parentID {
            guard parentID != id else { throw AtlasStoreError.collectionCycle }
            guard collectionExists(parentID) else { throw AtlasStoreError.collectionNotFound }
            guard !descendants(of: id).contains(where: { $0.id == parentID }) else {
                throw AtlasStoreError.collectionCycle
            }
            let deepestBelow = descendants(of: id).map { depth(of: $0.id) - depth(of: id) }.max() ?? 0
            guard depth(of: parentID) + 1 + deepestBelow < Self.maximumCollectionDepth else {
                throw AtlasStoreError.collectionTooDeep
            }
        }

        record.parentID = parentID
        try context.save()
        try refresh()
    }

    /// Moves a folder and puts it at a chosen position among its new siblings.
    ///
    /// Sort order is rewritten for the whole sibling group rather than nudged,
    /// so repeated drags cannot drift into ties that make the list jump around.
    public func moveCollection(id: String, toParent parentID: String?, atIndex index: Int) throws {
        try moveCollection(id: id, toParent: parentID)

        var siblings = childCollections(of: parentID).map(\.id)
        guard let currentIndex = siblings.firstIndex(of: id) else { return }
        siblings.remove(at: currentIndex)
        siblings.insert(id, at: min(max(index, 0), siblings.count))

        for (position, siblingID) in siblings.enumerated() {
            guard let record = try collectionRecord(id: siblingID) else { continue }
            record.sortOrder = (position + 1) * 10
        }
        try context.save()
        try refresh()
    }

    /// Deletes an empty collection. A folder holding notes or other folders is
    /// never removed silently — the caller is told what is still inside so the
    /// person can decide what happens to it.
    public func deleteCollection(id: String) throws {
        guard let record = try collectionRecord(id: id) else { throw AtlasStoreError.collectionNotFound }
        let noteCount = documents.count { $0.collectionID == id }
        let childCount = childCollections(of: id).count
        guard noteCount == 0, childCount == 0 else {
            throw AtlasStoreError.collectionNotEmpty(notes: noteCount, folders: childCount)
        }
        // Course context and course material belong to the folder, so they go
        // with it rather than lingering as rows nothing can reach.
        try setCourseContext(collectionID: id, briefing: "")
        try deleteAttachments(forCollection: id)
        context.delete(record)
        try context.save()
        try refresh()
    }

    // MARK: - Internals

    func collectionExists(_ id: String?) -> Bool {
        guard let id else { return false }
        return collections.contains { $0.id == id }
    }

    private func buildNodes(parentID: String?, depth: Int, visited: Set<String>) -> [AtlasCollectionNode] {
        guard depth < Self.maximumCollectionDepth else { return [] }
        return childCollections(of: parentID).compactMap { collection in
            // A parent chain corrupted from outside must not loop the sidebar.
            guard !visited.contains(collection.id) else { return nil }
            return AtlasCollectionNode(
                collection: collection,
                depth: depth,
                children: buildNodes(
                    parentID: collection.id,
                    depth: depth + 1,
                    visited: visited.union([collection.id])
                )
            )
        }
    }

    private func collectionRecord(id: String) throws -> AtlasCollectionRecord? {
        let target = id
        var descriptor = FetchDescriptor<AtlasCollectionRecord>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
