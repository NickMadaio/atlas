import Foundation

/*
 Where a finished lecture goes.

 Token matching gets a course code right and gets everything else wrong. It
 cannot tell that a new class called "CS 2100" belongs beside the student's
 other classes rather than at the top level next to them, because nothing about
 the characters says so — it is a judgement about what the folders mean.

 So the model is asked, with the real tree in front of it. Its answer is then
 checked against that tree: an id it invented, or a folder it was not offered,
 is discarded and the token matcher decides instead. The model chooses; it
 never gets to write.
*/

/// One folder, as the model is shown it.
public struct LecturePlacementOption: Sendable, Hashable, Codable {
    public let id: String
    /// Full path, so nesting is visible: "School › CS 2100".
    public let path: String
    public let summary: String
    public let noteCount: Int
    public let childCount: Int

    public init(id: String, path: String, summary: String, noteCount: Int, childCount: Int) {
        self.id = id
        self.path = path
        self.summary = summary
        self.noteCount = noteCount
        self.childCount = childCount
    }

    /// A folder holding folders and no notes of its own is a container — the
    /// kind of place a new class belongs inside.
    public var looksLikeAContainer: Bool { childCount > 0 && noteCount == 0 }
}

/// What the model replied. Every field optional: a model that answers half the
/// question still produces something checkable.
public struct LecturePlacementAnswer: Codable, Hashable, Sendable {
    public var folderID: String
    public var newFolderTitle: String
    public var newFolderParentID: String
    public var reason: String

    public init(folderID: String = "", newFolderTitle: String = "", newFolderParentID: String = "", reason: String = "") {
        self.folderID = folderID
        self.newFolderTitle = newFolderTitle
        self.newFolderParentID = newFolderParentID
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case folderID = "folderId"
        case newFolderTitle
        case newFolderParentID = "newFolderParentId"
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderID = container.lenientString(.folderID)
        newFolderTitle = container.lenientString(.newFolderTitle)
        newFolderParentID = container.lenientString(.newFolderParentID)
        reason = container.lenientString(.reason)
    }
}

public enum LecturePlacementService {
    public static let schemaDescription = """
    {
      "folderId": "the id of an existing folder, or empty to make a new one",
      "newFolderTitle": "name for the new folder, or empty when using an existing one",
      "newFolderParentId": "the id of the folder the new one goes inside, or empty for the top level",
      "reason": "one sentence on why"
    }
    """

    public static func user(
        structure: LectureStructure,
        hint: String?,
        options: [LecturePlacementOption]
    ) -> String {
        let tree = options.isEmpty
            ? "(no folders yet)"
            : options.map { option in
                var line = "- id: \(option.id) | \(option.path)"
                if !option.summary.trimmed.isEmpty {
                    line += " | \(option.summary.trimmed.bounded(120))"
                }
                line += " | \(option.noteCount) notes, \(option.childCount) folders inside"
                return line
            }.joined(separator: "\n")

        var lecture: [String] = []
        if let hint, !hint.trimmed.isEmpty {
            lecture.append("The student labelled this recording: \(hint.trimmed)")
        }
        if !structure.courseCode.trimmed.isEmpty {
            lecture.append("Course code heard: \(structure.courseCode.trimmed)")
        }
        if !structure.courseName.trimmed.isEmpty {
            lecture.append("Course name heard: \(structure.courseName.trimmed)")
        }
        if !structure.title.trimmed.isEmpty {
            lecture.append("Lecture title: \(structure.title.trimmed)")
        }
        if !structure.summary.trimmed.isEmpty {
            lecture.append("What it covered: \(structure.summary.trimmed.bounded(700))")
        }
        if !structure.topics.isEmpty {
            lecture.append("Topics: \(structure.topics.prefix(10).joined(separator: ", "))")
        }

        return """
        The student's folders:
        \(tree)

        The lecture:
        \(lecture.joined(separator: "\n"))

        Reply with one JSON object in exactly this shape:
        \(schemaDescription)
        """
    }

    /// Turns a reply into a decision, or nil when it cannot be trusted.
    ///
    /// Everything here is a check against the tree the model was shown. A
    /// hallucinated id, a parent that does not exist, or a new folder with no
    /// name all fail closed to the token matcher rather than filing a lecture
    /// somewhere arbitrary.
    public static func decision(
        from answer: LecturePlacementAnswer,
        options: [LecturePlacementOption]
    ) -> LectureClassifier.Decision? {
        let byID = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let chosenID = answer.folderID.trimmed
        if !chosenID.isEmpty, let option = byID[chosenID] {
            return LectureClassifier.Decision(
                existingCollectionID: option.id,
                proposedCollectionTitle: option.path,
                proposedCollectionSummary: option.summary,
                proposedParentID: nil,
                confidence: 0.9,
                reason: reasonLine(answer.reason, fallback: "The local model filed this into “\(option.path)”.")
            )
        }

        let title = answer.newFolderTitle.trimmed.keyboardNormalized
        guard !title.isEmpty, title.count <= 80 else { return nil }
        // A "new" folder whose name is one that already exists is the model
        // failing to notice the match; use the existing folder instead of
        // creating a duplicate beside it.
        if let twin = options.first(where: { $0.path.components(separatedBy: " › ").last?.caseInsensitiveCompare(title) == .orderedSame }) {
            return LectureClassifier.Decision(
                existingCollectionID: twin.id,
                proposedCollectionTitle: twin.path,
                proposedCollectionSummary: twin.summary,
                proposedParentID: nil,
                confidence: 0.85,
                reason: "“\(title)” already exists, so the notes went there rather than into a second folder with the same name."
            )
        }

        let parentID = answer.newFolderParentID.trimmed
        let parent = parentID.isEmpty ? nil : byID[parentID]
        // A named parent that is not in the tree is a hallucination; refusing
        // the whole answer is safer than quietly filing at the top level.
        guard parentID.isEmpty || parent != nil else { return nil }

        let where_ = parent.map { " inside “\($0.path)”" } ?? ""
        return LectureClassifier.Decision(
            existingCollectionID: nil,
            proposedCollectionTitle: title,
            proposedCollectionSummary: "Lectures and notes for \(title).",
            proposedParentID: parent?.id,
            confidence: 0.7,
            reason: reasonLine(answer.reason, fallback: "No folder matched, so “\(title)” was created\(where_).")
        )
    }

    private static func reasonLine(_ reason: String, fallback: String) -> String {
        let clean = reason.trimmed.keyboardNormalized
        guard !clean.isEmpty else { return fallback }
        return clean.bounded(300)
    }
}
