import Foundation
import SwiftData

/// One timestamped span of recognized speech.
public struct AtlasLectureSegment: Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = max(0, start)
        self.end = max(max(0, start), end)
        self.text = text
    }

    public var timecode: String { AtlasLectureSegment.timecode(for: start) }

    public static func timecode(for seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}

/// Where a lecture is in the capture-to-note pipeline. Every stage after
/// `recording` still owns durable audio, so no stage can lose the lecture.
public enum AtlasLectureStage: String, Codable, Sendable, CaseIterable {
    case recording
    case transcribing
    case structuring
    case filing
    case complete
    /// Audio and transcript are saved and notes exist, but the local model
    /// could not enrich them. Retrying enrichment is safe and non-destructive.
    case completeWithoutModel = "complete_without_model"
    case failed

    public var isTerminal: Bool {
        self == .complete || self == .completeWithoutModel || self == .failed
    }

    public var isWorking: Bool {
        self == .transcribing || self == .structuring || self == .filing
    }

    public var label: String {
        switch self {
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .structuring: "Writing notes"
        case .filing: "Filing"
        case .complete: "Ready"
        case .completeWithoutModel: "Ready (transcript only)"
        case .failed: "Needs attention"
        }
    }
}

/// The two documents one lecture produces. Both live in the ordinary note
/// library so search, the local assistant, and the agent bridge reach them
/// with no special casing.
public enum AtlasLectureDocumentRole: String, Codable, Sendable {
    /// Readable notes for the person who attended the lecture.
    case study
    /// The complete record an assistant reads: deep definitions, the full
    /// transcript, and explicit markers for what the audio did not settle.
    case depth

    public var categoryName: String {
        switch self {
        case .study: "Lecture"
        case .depth: "Lecture Source"
        }
    }
}

@Model
public final class AtlasLectureRecord {
    @Attribute(.unique) public var id: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: Double
    /// File name inside the app's own lectures directory. Never an absolute
    /// path, so the audio stays addressable if the container moves.
    public var audioFileName: String
    public var transcriptText: String
    public var segmentsJSON: String
    public var stageRaw: String
    public var failureReason: String?
    /// Optional hint the user typed before recording ("DS1800 Wednesday").
    public var courseHint: String?
    /// What the student told Atlas about this recording in particular, usually
    /// after reading notes that got something wrong. The default sits on the
    /// declaration so an existing store migrates without conversion.
    public var contextNote: String = ""
    /// True when the text came from a file or the clipboard rather than a
    /// microphone. Everything after transcription is identical, so an import is
    /// simply a lecture that skips the first step — but the interface must not
    /// offer to play audio that was never recorded.
    public var isImported: Bool = false
    public var titleGuess: String
    public var collectionID: String?
    public var studyDocumentID: String?
    public var depthDocumentID: String?
    public var modelIdentifier: String?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        durationSeconds: Double = 0,
        audioFileName: String,
        transcriptText: String = "",
        segmentsJSON: String = "[]",
        stage: AtlasLectureStage = .recording,
        failureReason: String? = nil,
        courseHint: String? = nil,
        contextNote: String = "",
        isImported: Bool = false,
        titleGuess: String = "Untitled lecture",
        collectionID: String? = nil,
        studyDocumentID: String? = nil,
        depthDocumentID: String? = nil,
        modelIdentifier: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.transcriptText = transcriptText
        self.segmentsJSON = segmentsJSON
        self.stageRaw = stage.rawValue
        self.failureReason = failureReason
        self.courseHint = courseHint
        self.contextNote = contextNote
        self.isImported = isImported
        self.titleGuess = titleGuess
        self.collectionID = collectionID
        self.studyDocumentID = studyDocumentID
        self.depthDocumentID = depthDocumentID
        self.modelIdentifier = modelIdentifier
        self.updatedAt = updatedAt
    }

    public var stage: AtlasLectureStage {
        get { AtlasLectureStage(rawValue: stageRaw) ?? .failed }
        set { stageRaw = newValue.rawValue }
    }
}

public struct AtlasLectureSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date?
    public let durationSeconds: Double
    public let audioFileName: String
    public let transcriptText: String
    public let segments: [AtlasLectureSegment]
    public let stage: AtlasLectureStage
    public let failureReason: String?
    public let courseHint: String?
    public let contextNote: String
    public let isImported: Bool
    public let titleGuess: String
    public let collectionID: String?
    public let studyDocumentID: String?
    public let depthDocumentID: String?
    public let modelIdentifier: String?
    public let updatedAt: Date

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Double,
        audioFileName: String,
        transcriptText: String,
        segments: [AtlasLectureSegment],
        stage: AtlasLectureStage,
        failureReason: String?,
        courseHint: String?,
        contextNote: String = "",
        isImported: Bool = false,
        titleGuess: String,
        collectionID: String?,
        studyDocumentID: String?,
        depthDocumentID: String?,
        modelIdentifier: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.audioFileName = audioFileName
        self.transcriptText = transcriptText
        self.segments = segments
        self.stage = stage
        self.failureReason = failureReason
        self.courseHint = courseHint
        self.contextNote = contextNote
        self.isImported = isImported
        self.titleGuess = titleGuess
        self.collectionID = collectionID
        self.studyDocumentID = studyDocumentID
        self.depthDocumentID = depthDocumentID
        self.modelIdentifier = modelIdentifier
        self.updatedAt = updatedAt
    }

    public var durationLabel: String {
        // An import has no length; showing 0:00 reads as a failed recording.
        if isImported { return "imported" }
        return AtlasLectureSegment.timecode(for: durationSeconds)
    }

    public var hasContextNote: Bool {
        contextNote.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    public var hasUsableTranscript: Bool {
        transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
    }
}

/// A lecture without its transcript, for listings. A full transcript per row
/// would make a list of a term's lectures megabytes of JSON.
public struct AtlasLectureSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let recordedAt: Date
    public let durationSeconds: Double
    public let stage: AtlasLectureStage
    public let collectionID: String?
    public let studyDocumentID: String?
    public let depthDocumentID: String?
    public let transcriptCharacters: Int
    public let modelIdentifier: String?

    public init(_ snapshot: AtlasLectureSnapshot) {
        id = snapshot.id
        title = snapshot.titleGuess
        recordedAt = snapshot.startedAt
        durationSeconds = snapshot.durationSeconds
        stage = snapshot.stage
        collectionID = snapshot.collectionID
        studyDocumentID = snapshot.studyDocumentID
        depthDocumentID = snapshot.depthDocumentID
        transcriptCharacters = snapshot.transcriptText.count
        modelIdentifier = snapshot.modelIdentifier
    }
}

public enum AtlasLectureCoding {
    public static func encodeSegments(_ segments: [AtlasLectureSegment]) -> String {
        guard let data = try? JSONEncoder().encode(segments),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    public static func decodeSegments(_ json: String) -> [AtlasLectureSegment] {
        guard let data = json.data(using: .utf8),
              let segments = try? JSONDecoder().decode([AtlasLectureSegment].self, from: data) else {
            return []
        }
        return segments
    }
}
