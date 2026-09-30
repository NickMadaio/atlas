import AtlasCore
import AuthenticationServices
import Foundation

@MainActor
final class AtlasAppModel: ObservableObject {
    @Published private(set) var library: AtlasLibraryStore?
    @Published private(set) var launchError: String?
    @Published var presentedError: String?
    #if os(macOS)
    @Published private(set) var agentBridge: AtlasAgentBridge?
    @Published private(set) var lectureCapture: LectureCaptureModel?
    #endif

    let auth: AuthSessionStore
    let environment: BackendConfiguration
    /// How Atlas writes notes. Owned here so the menu bar, the window, and the
    /// pipeline all read the same instructions.
    let settings = AtlasSettingsStore()

    init(bundle: Bundle = .main) {
        let environmentName = (bundle.object(forInfoDictionaryKey: "ATLAS_ENVIRONMENT") as? String) ?? "local"
        let rawURL = (bundle.object(forInfoDictionaryKey: "ATLAS_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = rawURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        environment = BackendConfiguration(
            environmentName: environmentName,
            baseURL: baseURL,
            isProduction: environmentName == "production"
        )
        auth = AuthSessionStore(
            client: AuthAPIClient(configuration: environment),
            tokenStore: KeychainTokenStore(service: bundle.bundleIdentifier ?? "com.nickmadaio.atlas")
        )

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--atlas-open-offline") {
            auth.continueOffline()
        }
        #endif

        do {
            let store = try AtlasLibraryStore()
            guard let seedURL = bundle.url(forResource: "SeedContent", withExtension: "json") else {
                throw AtlasLaunchError.missingSeedContent
            }
            let seedData = try Data(contentsOf: seedURL)
            try store.bootstrapIfNeeded(seedData: seedData)
            try store.hideExistingLectureSources()
            // Companion notes whose parent link was lost hang loose in the
            // folder, which makes one lecture look like eight.
            try store.relinkCompanionNotes()
            library = store
            #if os(macOS)
            agentBridge = AtlasAgentBridge(library: store, bundle: bundle)
            lectureCapture = LectureCaptureModel(library: store, settings: settings)
            #endif
        } catch {
            launchError = error.localizedDescription
        }

        if let rawURL, !rawURL.isEmpty, baseURL == nil {
            presentedError = "ATLAS_API_BASE_URL is not a valid URL. Remote sign-in is disabled until it is corrected."
        }
    }

    func report(_ error: Error) {
        presentedError = error.localizedDescription
    }
}

/// A plain message surfaced through the app's usual error path, for failures
/// that are already written for a person to read.
struct AtlasSimpleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AtlasLaunchError: LocalizedError {
    case missingSeedContent

    var errorDescription: String? {
        switch self {
        case .missingSeedContent:
            "Atlas could not find its bundled starter library. Rebuild the app with SeedContent.json included."
        }
    }
}

@MainActor
final class AuthSessionStore: ObservableObject {
    enum State: Equatable {
        case signedOut
        case guest
        case signedIn(AuthAccount)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var isSigningIn = false
    @Published var errorMessage: String?

    private let client: AuthAPIClient
    private let tokenStore: KeychainTokenStore
    private var accessToken: String?

    init(client: AuthAPIClient, tokenStore: KeychainTokenStore) {
        self.client = client
        self.tokenStore = tokenStore
    }

    func continueOffline() {
        errorMessage = nil
        state = .guest
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            errorMessage = error.localizedDescription
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let codeData = credential.authorizationCode,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let authorizationCode = String(data: codeData, encoding: .utf8) else {
                errorMessage = "Apple did not return the credentials required for secure server verification."
                return
            }
            isSigningIn = true
            errorMessage = nil
            Task {
                do {
                    let response = try await client.authenticateWithApple(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode
                    )
                    try tokenStore.saveRefreshToken(response.refreshToken)
                    accessToken = response.accessToken
                    state = .signedIn(response.account)
                    isSigningIn = false
                } catch {
                    errorMessage = error.localizedDescription
                    isSigningIn = false
                }
            }
        }
    }

    func signOut() {
        do {
            try tokenStore.deleteRefreshToken()
            accessToken = nil
            state = .signedOut
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
