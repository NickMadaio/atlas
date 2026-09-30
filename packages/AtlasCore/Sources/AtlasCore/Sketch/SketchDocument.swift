import Foundation

/// Everything the sketch pad needs to come back as you left it.
public struct SketchDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// The viewport width at which pen size 1 is one page unit wide.
    public static let referenceViewportWidth: Double = 1_000
    public static let penSizeRange: ClosedRange<Double> = 1...24

    public let version: Int
    public let page: SketchPage
    public let viewport: SketchViewport
    public let penSize: Double

    public init(page: SketchPage, viewport: SketchViewport, penSize: Double) {
        version = Self.currentVersion
        self.page = page
        self.viewport = viewport
        self.penSize = min(max(penSize, Self.penSizeRange.lowerBound), Self.penSizeRange.upperBound)
    }

    /// A 16:10 page roughly five trackpads wide, with the frame in the top-left
    /// corner so writing starts where a page does.
    public static func blank() -> SketchDocument {
        let size = SketchSize(width: 6_000, height: 3_750)
        let viewport = SketchViewport(
            pageSize: size,
            center: SketchPoint(x: 0, y: 0),
            width: referenceViewportWidth,
            aspect: 1.6
        )
        return SketchDocument(page: SketchPage(size: size), viewport: viewport, penSize: 4)
    }

    public func withPage(_ page: SketchPage) -> SketchDocument {
        SketchDocument(page: page, viewport: viewport, penSize: penSize)
    }

    public func withViewport(_ viewport: SketchViewport) -> SketchDocument {
        SketchDocument(page: page, viewport: viewport, penSize: penSize)
    }

    public func withPenSize(_ penSize: Double) -> SketchDocument {
        SketchDocument(page: page, viewport: viewport, penSize: penSize)
    }
}

public enum SketchDocumentFile {
    public struct UnsupportedVersion: LocalizedError {
        public let version: Int
        public var errorDescription: String? {
            "This sketch was saved by a newer Atlas (format \(version)) and cannot be opened here."
        }
    }

    public struct Missing: LocalizedError {
        public let fileName: String
        public var errorDescription: String? {
            "The sketch file \(fileName) is not on this device."
        }
    }

    /// For a sketch a note points at: unlike the pad, a missing file here is
    /// an error, never a blank page.
    public static func readSaved(from url: URL) throws -> SketchDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Missing(fileName: url.lastPathComponent)
        }
        return try read(from: url)
    }

    /// A missing file is a blank page. A file that exists but cannot be read
    /// throws, so a damaged sketch is never quietly overwritten with a new one.
    public static func read(from url: URL) throws -> SketchDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return .blank() }
        let document = try JSONDecoder().decode(SketchDocument.self, from: Data(contentsOf: url))
        guard document.version <= SketchDocument.currentVersion else {
            throw UnsupportedVersion(version: document.version)
        }
        return document
    }

    public static func write(_ document: SketchDocument, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
    }
}
