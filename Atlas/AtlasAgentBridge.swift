import AtlasCore
import Foundation

#if os(macOS)
@MainActor
final class AtlasAgentBridge: ObservableObject {
    enum Status: Equatable {
        case starting
        case ready
        case unavailable(String)

        var label: String {
            switch self {
            case .starting: "Starting"
            case .ready: "Ready"
            case .unavailable: "Needs attention"
            }
        }
    }

    private struct Metadata: Codable {
        let protocolVersion: Int
        let bundleIdentifier: String
        let appName: String
        let pendingDirectory: String
        let responsesDirectory: String
    }

    @Published private(set) var status: Status = .starting
    @Published private(set) var lastRequestAt: Date?

    private let library: AtlasLibraryStore
    private let fileManager: FileManager
    private let rootURL: URL
    private let pendingURL: URL
    private let responsesURL: URL
    private var pollingTask: Task<Void, Never>?

    init(library: AtlasLibraryStore, bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.library = library
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = applicationSupport.appending(path: "Atlas/AgentBridge", directoryHint: .isDirectory)
        pendingURL = rootURL.appending(path: "pending", directoryHint: .isDirectory)
        responsesURL = rootURL.appending(path: "responses", directoryHint: .isDirectory)

        do {
            try prepareDirectories(bundle: bundle)
            status = .ready
            pollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.processPendingRequests()
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    deinit { pollingTask?.cancel() }

    var locationDescription: String { rootURL.path(percentEncoded: false) }

    private func prepareDirectories(bundle: Bundle) throws {
        for directory in [rootURL, pendingURL, responsesURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        let metadata = Metadata(
            protocolVersion: AtlasAgentRequest.protocolVersion,
            bundleIdentifier: bundle.bundleIdentifier ?? "com.nickmadaio.atlas",
            appName: "Atlas",
            pendingDirectory: pendingURL.path(percentEncoded: false),
            responsesDirectory: responsesURL.path(percentEncoded: false)
        )
        let encoder = AtlasAgentJSON.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataURL = rootURL.appending(path: "bridge.json")
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
    }

    private func processPendingRequests() {
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            let urls = try fileManager.contentsOfDirectory(
                at: pendingURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            for requestURL in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(20) {
                let values = try requestURL.resourceValues(forKeys: keys)
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      requestURL.pathExtension == "json",
                      (values.fileSize ?? 0) <= 1_050_000 else {
                    try? fileManager.removeItem(at: requestURL)
                    continue
                }
                processRequest(at: requestURL)
            }
            cleanupOldResponses()
            status = .ready
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    private func processRequest(at url: URL) {
        let fileID = url.deletingPathExtension().lastPathComponent.lowercased()
        guard UUID(uuidString: fileID) != nil else {
            try? fileManager.removeItem(at: url)
            return
        }

        let response: AtlasAgentResponse
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe, .uncached])
            let decoder = AtlasAgentJSON.decoder()
            let request = try decoder.decode(AtlasAgentRequest.self, from: data)
            guard request.id.lowercased() == fileID else {
                throw AtlasAgentProtocolError.invalidRequestID
            }
            response = try library.handleAgentRequest(request)
        } catch {
            response = AtlasAgentResponse(id: fileID, error: error.localizedDescription)
        }

        do {
            let encoder = AtlasAgentJSON.encoder()
            encoder.outputFormatting = [.sortedKeys]
            let responseURL = responsesURL.appending(path: "\(fileID).json")
            try encoder.encode(response).write(to: responseURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: responseURL.path)
            try fileManager.removeItem(at: url)
            lastRequestAt = .now
        } catch {
            status = .unavailable(error.localizedDescription)
        }
    }

    private func cleanupOldResponses() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: responsesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        for url in urls {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff { try? fileManager.removeItem(at: url) }
        }
    }
}
#endif
