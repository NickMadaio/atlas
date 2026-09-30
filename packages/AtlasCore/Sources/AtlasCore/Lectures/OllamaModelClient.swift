import Foundation

/// Talks to an Ollama server running on this Mac.
///
/// Preferred when present: the models a student already has installed are far
/// larger than anything that fits in an app, and better notes come directly
/// out of that. Absence is normal and never an error — the caller falls back.
public struct OllamaModelClient: LectureModelClient {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!
    /// Ordered by how well they write study notes, best first. The first one
    /// actually installed is used.
    public static let preferredModels = [
        "gpt-oss:20b", "qwen3:30b", "qwen3.6:27b", "gemma4:31b", "llama3.2:3b"
    ]

    public let baseURL: URL
    public let model: String
    private let session: URLSession
    private let requestTimeout: TimeInterval

    public var identifier: String { "Ollama · \(model)" }

    public init(
        baseURL: URL = OllamaModelClient.defaultBaseURL,
        model: String,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 300
    ) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
        self.requestTimeout = requestTimeout
    }

    /// Returns a client for the best installed model, or nil when Ollama is
    /// not running or has none of the models we know how to use.
    public static func discover(
        baseURL: URL = OllamaModelClient.defaultBaseURL,
        session: URLSession = .shared,
        preferring preferred: String? = nil
    ) async -> OllamaModelClient? {
        guard (try? LoopbackGuard.validate(baseURL)) != nil else { return nil }
        guard let installed = await installedModels(baseURL: baseURL, session: session), !installed.isEmpty else {
            return nil
        }
        if let preferred, installed.contains(preferred) {
            return OllamaModelClient(baseURL: baseURL, model: preferred, session: session)
        }
        if let best = preferredModels.first(where: installed.contains) {
            return OllamaModelClient(baseURL: baseURL, model: best, session: session)
        }
        // An installed model we do not rank is still better than none, but
        // skip embedding-only models, which cannot answer a prompt.
        guard let any = installed.first(where: { !$0.contains("embed") }) else { return nil }
        return OllamaModelClient(baseURL: baseURL, model: any, session: session)
    }

    public static func installedModels(
        baseURL: URL = OllamaModelClient.defaultBaseURL,
        session: URLSession = .shared
    ) async -> [String]? {
        guard (try? LoopbackGuard.validate(baseURL)) != nil else { return nil }
        var request = URLRequest(url: baseURL.appending(path: "api/tags"))
        request.timeoutInterval = 4
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let payload = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return nil
        }
        return payload.models.map(\.name)
    }

    public func isReachable() async -> Bool {
        guard let installed = await Self.installedModels(baseURL: baseURL, session: session) else { return false }
        return installed.contains(model)
    }

    public func complete(system: String, user: String) async throws -> String {
        try LoopbackGuard.validate(baseURL)

        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: system),
                    .init(role: "user", content: user)
                ],
                stream: false,
                format: "json",
                options: .init(temperature: 0.2, numberOfContextTokens: 16_384)
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LectureModelError.transportFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LectureModelError.transportFailure("The local model did not return an HTTP response.")
        }
        guard http.statusCode == 200 else {
            throw LectureModelError.transportFailure("The local model returned status \(http.statusCode).")
        }

        guard let payload = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw LectureModelError.unusableOutput
        }
        let content = payload.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw LectureModelError.emptyResponse }
        return content
    }

    // MARK: - Wire types

    private struct TagsResponse: Decodable {
        struct Entry: Decodable { let name: String }
        let models: [Entry]
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
            let numberOfContextTokens: Int

            enum CodingKeys: String, CodingKey {
                case temperature
                case numberOfContextTokens = "num_ctx"
            }
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let format: String
        let options: Options
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
}
