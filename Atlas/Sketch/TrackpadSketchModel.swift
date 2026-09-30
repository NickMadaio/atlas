#if os(macOS)
import AtlasCore
import Foundation

/// State for the trackpad sketch pad: the page, where the trackpad frame sits
/// on it, the stroke under the finger, and the keys moving the frame.
@MainActor
final class TrackpadSketchModel: ObservableObject {
    enum PanKey: Character, CaseIterable {
        case up = "w", left = "a", down = "s", right = "d"

        var direction: (dx: Double, dy: Double) {
            switch self {
            case .up: (0, -1)
            case .left: (-1, 0)
            case .down: (0, 1)
            case .right: (1, 0)
            }
        }
    }

    /// Frame widths per second while a movement key is held.
    static let panSpeed = 0.9
    static let zoomStep = 1.25

    @Published private(set) var document: SketchDocument
    @Published private(set) var liveStroke: SketchStroke?
    @Published private(set) var penLocation: SketchPoint?
    @Published var isWriting = false
    @Published private(set) var saveError: String?

    private var undoStack: [SketchPage] = []
    private var filter = SketchInputFilter()
    private var heldKeys: Set<PanKey> = []
    private var panTimer: Timer?
    private var lastPanTick: Date?
    private let fileURL: URL

    var canUndo: Bool { !undoStack.isEmpty }

    init(fileURL: URL = TrackpadSketchModel.defaultFileURL()) {
        self.fileURL = fileURL
        do {
            document = try SketchDocumentFile.read(from: fileURL)
        } catch {
            document = .blank()
            saveError = Self.setAside(damagedFileAt: fileURL, because: error)
        }
    }

    /// Moves an unreadable sketch out of the way so the next save cannot
    /// overwrite it, and says where it went.
    private static func setAside(damagedFileAt url: URL, because error: Error) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = url.deletingLastPathComponent().appending(path: "pad-unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return "The saved sketch could not be opened (\(error.localizedDescription)). It was kept as \(aside.lastPathComponent) and a blank page is showing."
        } catch let moveError {
            return "The saved sketch could not be opened (\(error.localizedDescription)) or moved aside (\(moveError.localizedDescription)). Drawing now will replace it."
        }
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Atlas/Sketches/pad.json")
    }

    // MARK: - Pen

    func touchBegan(at normalized: SketchPoint, trackpadAspect: Double?) {
        if let trackpadAspect, abs(trackpadAspect - document.viewport.aspect) > 0.001 {
            document = document.withViewport(document.viewport.withAspect(trackpadAspect))
        }
        filter = SketchInputFilter(smoothing: 0.35, minimumDistance: minimumSampleDistance)
        let point = document.viewport.pagePoint(forTouchAt: normalized)
        penLocation = point
        let width = document.viewport.pageLineWidth(forPenSize: document.penSize)
        liveStroke = filter.accept(point).map { SketchStroke(width: width, points: [$0]) }
    }

    func touchMoved(to normalized: SketchPoint) {
        guard let stroke = liveStroke else { return }
        let point = document.viewport.pagePoint(forTouchAt: normalized)
        penLocation = point
        if let accepted = filter.accept(point) {
            liveStroke = stroke.appending(accepted)
        }
    }

    func touchEnded() {
        defer {
            liveStroke = nil
            penLocation = nil
        }
        guard let stroke = liveStroke else { return }
        commit(document.page.adding(stroke.smoothed()))
    }

    func touchCancelled() {
        liveStroke = nil
        penLocation = nil
    }

    /// Jitter threshold in page units: about a tenth of a percent of the frame,
    /// so it means the same distance on the trackpad at every zoom.
    private var minimumSampleDistance: Double { document.viewport.width * 0.0012 }

    // MARK: - Editing

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        document = document.withPage(previous)
        save()
    }

    func clear() {
        guard !document.page.strokes.isEmpty else { return }
        commit(document.page.cleared())
    }

    /// Writes the page as it stands to its own file and returns its id.
    func saveSnapshot(to directory: URL) throws -> UUID {
        guard !document.page.strokes.isEmpty else {
            throw AtlasSimpleError(message: "There is nothing on the page to save.")
        }
        let id = UUID()
        try SketchDocumentFile.write(document, to: directory.appending(path: "\(id.uuidString.lowercased()).json"))
        return id
    }

    /// Clears the page for the next sketch; undo brings the old one back.
    func startFreshPage() {
        clear()
        document = document.withViewport(SketchDocument.blank().viewport.withAspect(document.viewport.aspect))
        save()
    }

    func setPenSize(_ size: Double) {
        document = document.withPenSize(size)
        save()
    }

    func adjustPenSize(by delta: Double) {
        setPenSize(document.penSize + delta)
    }

    private func commit(_ page: SketchPage) {
        undoStack = Array((undoStack + [document.page]).suffix(200))
        document = document.withPage(page)
        save()
    }

    // MARK: - Frame movement

    func zoom(in zoomIn: Bool) {
        let factor = zoomIn ? Self.zoomStep : 1 / Self.zoomStep
        document = document.withViewport(document.viewport.zoomed(by: factor))
        save()
    }

    func press(_ key: PanKey) {
        heldKeys.insert(key)
        guard panTimer == nil else { return }
        lastPanTick = Date()
        panTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickPan() }
        }
    }

    func release(_ key: PanKey) {
        heldKeys.remove(key)
        if heldKeys.isEmpty { stopPanning() }
    }

    func releaseAllKeys() {
        heldKeys.removeAll()
        stopPanning()
    }

    private func tickPan() {
        let now = Date()
        let elapsed = min(now.timeIntervalSince(lastPanTick ?? now), 0.1)
        lastPanTick = now
        let direction = heldKeys.reduce((dx: 0.0, dy: 0.0)) { sum, key in
            (sum.dx + key.direction.dx, sum.dy + key.direction.dy)
        }
        let distance = document.viewport.width * Self.panSpeed * elapsed
        document = document.withViewport(
            document.viewport.panned(dx: direction.dx * distance, dy: direction.dy * distance)
        )
    }

    private func stopPanning() {
        guard panTimer != nil else { return }
        panTimer?.invalidate()
        panTimer = nil
        lastPanTick = nil
        save()
    }

    // MARK: - Saving

    private func save() {
        do {
            try SketchDocumentFile.write(document, to: fileURL)
            saveError = nil
        } catch {
            saveError = "The sketch could not be saved: \(error.localizedDescription)"
        }
    }
}
#endif
