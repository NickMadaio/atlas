import Foundation

/// A local text model that can turn a transcript into structured notes.
/// Every conforming client runs on this machine; lecture content is personal
/// and never leaves the device.
public protocol LectureModelClient: Sendable {
    /// Shown to the user and recorded in the note, so it is always visible
    /// which model wrote a given set of notes.
    var identifier: String { get }
    /// How much transcript one request may carry. A 3B on-device model needs a
    /// far smaller slice than a 20B model in Ollama, so this is a requirement
    /// rather than an extension default — the wrong budget silently truncates.
    var chunkCharacterBudget: Int { get }
    func isReachable() async -> Bool
    func complete(system: String, user: String) async throws -> String
}

public enum LectureModelError: LocalizedError, Equatable {
    case notReachable(String)
    case nonLoopbackHost(String)
    case emptyResponse
    case transportFailure(String)
    case unusableOutput

    public var errorDescription: String? {
        switch self {
        case let .notReachable(name):
            "\(name) is not running on this Mac, so Atlas could not write notes from the transcript."
        case let .nonLoopbackHost(host):
            "Atlas only sends lecture text to a model on this machine. “\(host)” is not a local address."
        case .emptyResponse:
            "The local model returned nothing."
        case let .transportFailure(reason):
            "Atlas could not reach the local model: \(reason)"
        case .unusableOutput:
            "The local model's reply could not be read as lecture notes."
        }
    }
}

public enum LoopbackGuard {
    private static let allowedHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0:0:0:0:0:0:0:1"]

    /// Lecture transcripts are personal recordings of identifiable people. A
    /// model endpoint is therefore allowed to be configured, but only ever to
    /// an address on this machine — a typo or a pasted remote URL must not
    /// quietly turn local note-taking into an upload.
    public static func validate(_ url: URL) throws {
        let host = (url.host() ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard allowedHosts.contains(host) else {
            throw LectureModelError.nonLoopbackHost(url.host() ?? url.absoluteString)
        }
    }
}

extension LectureModelClient {
    public var chunkCharacterBudget: Int { TranscriptChunker.defaultChunkCharacters }
}
