import Foundation

public enum AtlasAgentOperation: String, Codable, Sendable {
    case health
    case listCollections = "collections.list"
    case searchNotes = "notes.search"
    case readNote = "notes.read"
    case createNote = "notes.create"
    case updateNote = "notes.update"
    case listLectures = "lectures.list"
    case readLecture = "lectures.read"
}

public struct AtlasAgentArguments: Codable, Sendable, Equatable {
    public var collectionID: String?
    public var noteID: String?
    public var lectureID: String?
    public var query: String?
    public var title: String?
    public var summary: String?
    public var category: String?
    public var markdown: String?
    public var expectedUpdatedAt: Date?
    public var limit: Int?

    public init(
        collectionID: String? = nil,
        noteID: String? = nil,
        lectureID: String? = nil,
        query: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        category: String? = nil,
        markdown: String? = nil,
        expectedUpdatedAt: Date? = nil,
        limit: Int? = nil
    ) {
        self.collectionID = collectionID
        self.noteID = noteID
        self.lectureID = lectureID
        self.query = query
        self.title = title
        self.summary = summary
        self.category = category
        self.markdown = markdown
        self.expectedUpdatedAt = expectedUpdatedAt
        self.limit = limit
    }
}

public struct AtlasAgentRequest: Codable, Sendable, Equatable {
    public static let protocolVersion = 1

    public let version: Int
    public let id: String
    public let operation: AtlasAgentOperation
    public let arguments: AtlasAgentArguments

    public init(
        id: String = UUID().uuidString.lowercased(),
        operation: AtlasAgentOperation,
        arguments: AtlasAgentArguments = .init()
    ) {
        self.version = Self.protocolVersion
        self.id = id
        self.operation = operation
        self.arguments = arguments
    }
}

public struct AtlasAgentPayload: Codable, Sendable, Equatable {
    public var message: String?
    public var collections: [AtlasCollectionSnapshot]?
    public var notes: [AtlasDocumentSnapshot]?
    public var note: AtlasDocumentSnapshot?
    public var noteID: String?
    public var lectures: [AtlasLectureSummary]?
    public var lecture: AtlasLectureSnapshot?

    public init(
        message: String? = nil,
        collections: [AtlasCollectionSnapshot]? = nil,
        notes: [AtlasDocumentSnapshot]? = nil,
        note: AtlasDocumentSnapshot? = nil,
        noteID: String? = nil,
        lectures: [AtlasLectureSummary]? = nil,
        lecture: AtlasLectureSnapshot? = nil
    ) {
        self.message = message
        self.collections = collections
        self.notes = notes
        self.note = note
        self.noteID = noteID
        self.lectures = lectures
        self.lecture = lecture
    }
}

public struct AtlasAgentResponse: Codable, Sendable, Equatable {
    public let version: Int
    public let id: String
    public let ok: Bool
    public let payload: AtlasAgentPayload?
    public let error: String?

    public init(id: String, payload: AtlasAgentPayload) {
        self.version = AtlasAgentRequest.protocolVersion
        self.id = id
        self.ok = true
        self.payload = payload
        self.error = nil
    }

    public init(id: String, error: String) {
        self.version = AtlasAgentRequest.protocolVersion
        self.id = id
        self.ok = false
        self.payload = nil
        self.error = error
    }
}

public enum AtlasAgentProtocolError: LocalizedError {
    case unsupportedVersion
    case invalidRequestID
    case missingArgument(String)
    case updateConflict

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            "This Atlas agent request uses an unsupported protocol version."
        case .invalidRequestID:
            "The Atlas agent request ID is invalid."
        case let .missingArgument(name):
            "The Atlas agent request is missing \(name)."
        case .updateConflict:
            "The note changed after the agent read it. Read it again before updating."
        }
    }
}

public enum AtlasAgentJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let ordinary = ISO8601DateFormatter()
            ordinary.formatOptions = [.withInternetDateTime]
            if let date = ordinary.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected an ISO 8601 date."
            )
        }
        return decoder
    }
}
