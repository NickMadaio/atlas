import Foundation

/// Chooses which class a finished lecture belongs to.
///
/// Course identity is messy: the lecturer says "DS eighteen hundred", the model
/// writes `DS1800`, and the collection is called "DS 1800 — Data Science". The
/// comparison therefore runs on tokens with letter/digit boundaries split, so
/// all three forms meet. When nothing is confident enough, filing goes to a
/// clearly named holding collection rather than guessing a wrong class.
public enum LectureClassifier {
    public static let matchThreshold = 0.42
    public static let unfiledCollectionTitle = "Unfiled Lectures"

    public struct Decision: Sendable, Equatable {
        public let existingCollectionID: String?
        public let proposedCollectionTitle: String
        public let proposedCollectionSummary: String
        /// Where a newly created folder should sit. A new class belongs beside
        /// the student's other classes, not at the top level next to the folder
        /// that holds them.
        public let proposedParentID: String?
        public let confidence: Double
        public let reason: String

        public var createsCollection: Bool { existingCollectionID == nil }

        public init(
            existingCollectionID: String?,
            proposedCollectionTitle: String,
            proposedCollectionSummary: String,
            proposedParentID: String? = nil,
            confidence: Double,
            reason: String
        ) {
            self.existingCollectionID = existingCollectionID
            self.proposedCollectionTitle = proposedCollectionTitle
            self.proposedCollectionSummary = proposedCollectionSummary
            self.proposedParentID = proposedParentID
            self.confidence = confidence
            self.reason = reason
        }
    }

    public static func decide(
        structure: LectureStructure,
        hint: String?,
        collections: [AtlasCollectionSnapshot],
        noteCountFor: (String) -> Int = { _ in 0 }
    ) -> Decision {
        let identities = identityCandidates(structure: structure, hint: hint)
        var best: (collection: AtlasCollectionSnapshot, score: Double, identity: String)?

        for collection in collections {
            let haystack = tokens(collection.title).union(tokens(collection.summary))
            for identity in identities {
                let score = similarity(tokens(identity), haystack)
                if score > (best?.score ?? 0) {
                    best = (collection, score, identity)
                }
            }
        }

        if let best, best.score >= matchThreshold {
            return Decision(
                existingCollectionID: best.collection.id,
                proposedCollectionTitle: best.collection.title,
                proposedCollectionSummary: best.collection.summary,
                confidence: min(1, best.score),
                reason: "Matched “\(best.identity)” to the existing collection “\(best.collection.title)”."
            )
        }

        guard let newTitle = identities.first, !newTitle.isEmpty else {
            let existing = collections.first { $0.title.caseInsensitiveCompare(unfiledCollectionTitle) == .orderedSame }
            return Decision(
                existingCollectionID: existing?.id,
                proposedCollectionTitle: unfiledCollectionTitle,
                proposedCollectionSummary: "Recordings Atlas could not confidently assign to a class. Move them into the right collection when you get a moment.",
                confidence: 0,
                reason: "The recording did not name a course, so it is held here instead of being filed into the wrong class."
            )
        }

        let container = courseContainerID(in: collections, noteCountFor: noteCountFor)
        let containerTitle = container.flatMap { id in collections.first { $0.id == id }?.title }
        let placement = containerTitle.map { " inside “\($0)”, where the other classes already live" } ?? ""
        return Decision(
            existingCollectionID: nil,
            proposedCollectionTitle: newTitle,
            proposedCollectionSummary: "Lectures and notes for \(newTitle).",
            proposedParentID: container,
            confidence: min(0.4, best?.score ?? 0),
            reason: "No existing collection matched “\(newTitle)”, so a new one was created for it\(placement)."
        )
    }

    /// The folder new classes belong inside.
    ///
    /// Without a model to ask, the tree's own shape is the evidence: a folder
    /// that holds other folders and no notes of its own exists to group things,
    /// and what it groups is whatever is already inside it. That is how
    /// "School" gets found without anyone having to name it School.
    ///
    /// Ties break towards the shallowest folder and then alphabetically, so the
    /// answer does not change between two runs on the same library.
    static func courseContainerID(
        in collections: [AtlasCollectionSnapshot],
        noteCountFor: (String) -> Int
    ) -> String? {
        func depth(of collection: AtlasCollectionSnapshot) -> Int {
            var result = 0
            var seen: Set<String> = [collection.id]
            var current = collection
            while let parentID = current.parentID,
                  let parent = collections.first(where: { $0.id == parentID }),
                  seen.insert(parent.id).inserted {
                result += 1
                current = parent
            }
            return result
        }

        func childCount(_ id: String) -> Int {
            collections.count { $0.parentID == id }
        }

        let candidates = collections.filter { childCount($0.id) >= 2 && noteCountFor($0.id) == 0 }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { left, right in
            let leftChildren = childCount(left.id)
            let rightChildren = childCount(right.id)
            if leftChildren != rightChildren { return leftChildren < rightChildren }
            let leftDepth = depth(of: left)
            let rightDepth = depth(of: right)
            if leftDepth != rightDepth { return leftDepth > rightDepth }
            return left.title > right.title
        }?.id
    }

    /// Ordered strongest-identity-first: a code the lecturer read out is more
    /// reliable than a title the model invented.
    static func identityCandidates(structure: LectureStructure, hint: String?) -> [String] {
        var candidates: [String] = []
        let hintValue = (hint ?? "").trimmed
        if !hintValue.isEmpty { candidates.append(hintValue) }

        let code = structure.courseCode.trimmed
        let name = structure.courseName.trimmed
        if !code.isEmpty, !name.isEmpty { candidates.append("\(code) \(name)") }
        if !code.isEmpty { candidates.append(code) }
        if !name.isEmpty { candidates.append(name) }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }

    static func similarity(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        // A course-code token ("ds1800") present on both sides is decisive on
        // its own; overlap ratios would dilute it among generic title words.
        let sharedCodes = left.intersection(right).filter(isCourseCode)
        if !sharedCodes.isEmpty { return 0.95 }

        let shared = left.intersection(right)
        guard !shared.isEmpty else { return 0 }
        return Double(shared.count) / Double(min(left.count, right.count))
    }

    static func isCourseCode(_ token: String) -> Bool {
        let hasLetter = token.contains { $0.isLetter }
        let hasDigit = token.contains { $0.isNumber }
        return hasLetter && hasDigit && token.count >= 4
    }

    /// Splits on non-alphanumerics and again at letter/digit boundaries, then
    /// keeps both halves and the joined form so "DS 1800", "DS1800" and
    /// "ds-1800" all produce the token `ds1800`.
    static func tokens(_ value: String) -> Set<String> {
        let pieces = value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        var result = Set<String>()
        var previous: String?
        for piece in pieces {
            result.insert(piece)
            let letters = piece.prefix { $0.isLetter }
            let digits = piece.drop { $0.isLetter }
            if !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber) {
                result.insert(String(letters))
                result.insert(String(digits))
            }
            if let previous,
               previous.allSatisfy(\.isLetter),
               piece.allSatisfy(\.isNumber),
               previous.count <= 4 {
                result.insert(previous + piece)
            }
            previous = piece
        }
        return result.subtracting(stopWords)
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "notes", "note", "class", "course", "lecture", "lectures", "of", "a", "an", "my"
    ]
}
