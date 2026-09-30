import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model, used when Ollama is not running.
///
/// It is much smaller than the models a student installs themselves, so it
/// gets a smaller slice of transcript per request, but it needs no setup and
/// no network at all — which makes it the dependable floor under the feature.
@available(macOS 26.0, iOS 26.0, *)
public struct AppleLocalModelClient: LectureModelClient {
    public let identifier = "Apple on-device model"
    public var chunkCharacterBudget: Int { 2_800 }

    public init() {}

    public static var isSupported: Bool {
        SystemLanguageModel().isAvailable
    }

    public func isReachable() async -> Bool {
        SystemLanguageModel().isAvailable
    }

    public func complete(system: String, user: String) async throws -> String {
        let model = SystemLanguageModel()
        guard model.isAvailable else {
            throw LectureModelError.notReachable(identifier)
        }
        let session = LanguageModelSession(model: model, instructions: system)
        do {
            let response = try await session.respond(to: user)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { throw LectureModelError.emptyResponse }
            return content
        } catch let error as LectureModelError {
            throw error
        } catch {
            throw LectureModelError.transportFailure(error.localizedDescription)
        }
    }
}
#endif
