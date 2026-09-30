import Foundation
import SwiftData

/// A document attached to a lecture: slides, a handout, a reading.
///
/// The extracted text is stored alongside the file so note writing never has
/// to re-parse a PDF, and so an assistant reading the library can use the
/// material even if the original file is later moved away.
@Model
public final class AtlasAttachmentRecord {
    @Attribute(.unique) public var id: String
    /// The lecture this belongs to, or empty for material attached to a course
    /// rather than to one recording.
    public var lectureID: String
    /// Set instead of `lectureID` for course material — a syllabus, a module
    /// outline — that applies to every lecture in the class. The default sits
    /// on the declaration so an existing store migrates without conversion.
    public var collectionID: String? = nil
    /// Name inside Atlas's own attachments directory, never a path.
    public var fileName: String
    /// The name the file had when it was added, shown to the user.
    public var displayName: String
    public var extractedText: String
    /// Page-by-page text, so a note can cite a slide number. The default sits
    /// on the declaration so the schema can migrate an existing store.
    public var pagesJSON: String = "[]"
    public var byteSize: Int
    public var addedAt: Date
    /// Set when text could not be read, so the reason is visible rather than
    /// the attachment silently contributing nothing.
    public var extractionNote: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        lectureID: String,
        collectionID: String? = nil,
        fileName: String,
        displayName: String,
        extractedText: String = "",
        pagesJSON: String = "[]",
        byteSize: Int = 0,
        addedAt: Date = .now,
        extractionNote: String? = nil
    ) {
        self.id = id
        self.lectureID = lectureID
        self.collectionID = collectionID
        self.fileName = fileName
        self.displayName = displayName
        self.extractedText = extractedText
        self.pagesJSON = pagesJSON
        self.byteSize = byteSize
        self.addedAt = addedAt
        self.extractionNote = extractionNote
    }
}

public struct AtlasAttachmentSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let lectureID: String
    /// Set when this is course material rather than a lecture's own slides.
    public let collectionID: String?
    public let fileName: String
    public let displayName: String
    public let extractedText: String
    public let pages: [AttachmentTextExtractor.Page]
    public let byteSize: Int
    public let addedAt: Date
    public let extractionNote: String?

    public init(
        id: String,
        lectureID: String,
        collectionID: String? = nil,
        fileName: String,
        displayName: String,
        extractedText: String,
        pages: [AttachmentTextExtractor.Page] = [],
        byteSize: Int,
        addedAt: Date,
        extractionNote: String?
    ) {
        self.id = id
        self.lectureID = lectureID
        self.collectionID = collectionID
        self.fileName = fileName
        self.displayName = displayName
        self.extractedText = extractedText
        self.pages = pages
        self.byteSize = byteSize
        self.addedAt = addedAt
        self.extractionNote = extractionNote
    }

    /// Course material applies to every lecture in the class, not one of them.
    public var isCourseMaterial: Bool { collectionID != nil }

    public var hasText: Bool {
        extractedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
    }

    public var wordCount: Int {
        extractedText.split(whereSeparator: \.isWhitespace).count
    }

    /// "slide" reads right for a deck, "page" for a reading. Taken from the
    /// file type first, since that is a fact rather than a guess at the name.
    public var pageNoun: String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pptx", "key": return "slide"
        default: break
        }
        return displayName.lowercased().contains("slide") ? "slide" : "page"
    }

    public var pageLabel: String? {
        guard pages.count > 1 else { return nil }
        return "\(pages.count) \(pageNoun)s"
    }

    public var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }
}


public enum AttachmentPageCoding {
    public static func encode(_ pages: [AttachmentTextExtractor.Page]) -> String {
        guard let data = try? JSONEncoder().encode(pages),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    public static func decode(_ json: String) -> [AttachmentTextExtractor.Page] {
        guard let data = json.data(using: .utf8),
              let pages = try? JSONDecoder().decode([AttachmentTextExtractor.Page].self, from: data) else {
            return []
        }
        return pages
    }
}
