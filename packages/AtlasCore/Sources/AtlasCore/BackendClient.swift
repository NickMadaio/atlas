import Foundation

public struct BackendConfiguration: Sendable {
    public let environmentName: String
    public let baseURL: URL?
    public let isProduction: Bool

    public init(environmentName: String, baseURL: URL?, isProduction: Bool) {
        self.environmentName = environmentName
        self.baseURL = baseURL
        self.isProduction = isProduction
    }
}

public struct AuthAccount: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String?
    public let email: String?
}

public struct AuthSessionResponse: Codable, Sendable {
    public let account: AuthAccount
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
}

public struct APIErrorEnvelope: Codable, Sendable {
    public let code: String
    public let message: String
    public let field: String?
    public let requestID: String?

    enum CodingKeys: String, CodingKey {
        case code, message, field
        case requestID = "request_id"
    }
}

public actor AuthAPIClient {
    private struct AppleAuthRequest: Encodable {
        let identityToken: String
        let authorizationCode: String
        let idempotencyKey: String

        enum CodingKeys: String, CodingKey {
            case identityToken = "identity_token"
            case authorizationCode = "authorization_code"
            case idempotencyKey = "idempotency_key"
        }
    }

    private let configuration: BackendConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(configuration: BackendConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func authenticateWithApple(
        identityToken: String,
        authorizationCode: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> AuthSessionResponse {
        guard let baseURL = configuration.baseURL else {
            throw BackendClientError.configurationMissing
        }
        guard baseURL.scheme == "https" else {
            throw BackendClientError.insecureBaseURL
        }
        let endpoint = baseURL.appending(path: "v1/auth/apple")
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(
            AppleAuthRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                idempotencyKey: idempotencyKey.uuidString
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw BackendClientError.server(envelope)
            }
            throw BackendClientError.httpStatus(http.statusCode)
        }
        return try decoder.decode(AuthSessionResponse.self, from: data)
    }
}

public enum BackendClientError: LocalizedError {
    case configurationMissing
    case insecureBaseURL
    case invalidResponse
    case httpStatus(Int)
    case server(APIErrorEnvelope)

    public var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "Remote sign-in is not connected yet. Configure an HTTPS Atlas backend or continue offline."
        case .insecureBaseURL:
            "Atlas refuses to send account credentials over a non-HTTPS connection."
        case .invalidResponse:
            "The sign-in service returned an invalid response."
        case let .httpStatus(status):
            "The sign-in service returned HTTP \(status)."
        case let .server(error):
            error.message
        }
    }
}
