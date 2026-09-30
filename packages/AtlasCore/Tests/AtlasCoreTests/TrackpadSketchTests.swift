import Foundation
import Testing
@testable import AtlasCore

@Suite("Trackpad sketch — absolute mapping")
struct SketchViewportTests {
    private let page = SketchSize(width: 4_000, height: 2_500)

    private func viewport(width: Double = 1_000, aspect: Double = 1.6) -> SketchViewport {
        SketchViewport(pageSize: page, center: SketchPoint(x: 2_000, y: 1_250), width: width, aspect: aspect)
    }

    @Test("A finger 25% from the left and 40% from the top lands 25%/40% into the frame")
    func mapsProportionally() {
        let frame = viewport()
        // NSTouch reports y from the bottom of the trackpad, so 40% from the top is 0.6.
        let point = frame.pagePoint(forTouchAt: SketchPoint(x: 0.25, y: 0.6))
        let rect = frame.rect
        #expect(abs(point.x - (rect.minX + 0.25 * rect.width)) < 1e-9)
        #expect(abs(point.y - (rect.minY + 0.40 * rect.height)) < 1e-9)
    }

    @Test("The trackpad's corners are the frame's corners")
    func cornersMapToCorners() {
        let frame = viewport()
        let rect = frame.rect
        let topLeft = frame.pagePoint(forTouchAt: SketchPoint(x: 0, y: 1))
        let bottomRight = frame.pagePoint(forTouchAt: SketchPoint(x: 1, y: 0))
        #expect(topLeft == SketchPoint(x: rect.minX, y: rect.minY))
        #expect(bottomRight == SketchPoint(x: rect.maxX, y: rect.maxY))
    }

    @Test("A touch reported just outside 0…1 is held to the frame's edge")
    func clampsOutOfRangeTouches() {
        let frame = viewport()
        let point = frame.pagePoint(forTouchAt: SketchPoint(x: -0.02, y: 1.03))
        #expect(point == SketchPoint(x: frame.rect.minX, y: frame.rect.minY))
    }

    @Test("The frame takes the trackpad's shape")
    func frameHasTrackpadAspect() {
        let frame = viewport(width: 1_000, aspect: 1.6)
        #expect(abs(frame.rect.height - 625) < 1e-9)
        let reshaped = frame.withAspect(2.0)
        #expect(abs(reshaped.rect.height - 500) < 1e-9)
        #expect(reshaped.center == frame.center)
    }

    @Test("Panning moves the frame without changing its size")
    func panningKeepsScale() {
        let frame = viewport()
        let moved = frame.panned(dx: 200, dy: -100)
        #expect(moved.center == SketchPoint(x: 2_200, y: 1_150))
        #expect(moved.width == frame.width)
    }

    @Test("The frame cannot be panned off the page")
    func panningIsClampedToPage() {
        let frame = viewport()
        let far = frame.panned(dx: 1_000_000, dy: -1_000_000)
        #expect(abs(far.rect.maxX - page.width) < 1e-9)
        #expect(abs(far.rect.minY) < 1e-9)
    }

    @Test("Zooming in makes the frame smaller on the page, so writing lands smaller")
    func zoomInShrinksFrame() {
        let frame = viewport(width: 1_000)
        let zoomed = frame.zoomed(by: 2)
        #expect(abs(zoomed.width - 500) < 1e-9)
        #expect(zoomed.center == frame.center)

        // The same stroke across the trackpad covers half the page distance.
        let before = frame.pagePoint(forTouchAt: SketchPoint(x: 1, y: 0.5)).x
            - frame.pagePoint(forTouchAt: SketchPoint(x: 0, y: 0.5)).x
        let after = zoomed.pagePoint(forTouchAt: SketchPoint(x: 1, y: 0.5)).x
            - zoomed.pagePoint(forTouchAt: SketchPoint(x: 0, y: 0.5)).x
        #expect(abs(after - before / 2) < 1e-9)
    }

    @Test("Zoom is bounded at both ends")
    func zoomIsBounded() {
        let frame = viewport()
        #expect(frame.zoomed(by: 1_000).width == SketchViewport.minimumWidth)
        #expect(frame.zoomed(by: 0.000_1).width <= page.width)
        #expect(frame.zoomed(by: 0.000_1).rect.height <= page.height + 1e-9)
    }

    @Test("Pen width is in trackpad terms, so a zoomed-in line is thinner on the page")
    func penWidthFollowsZoom() {
        let frame = viewport(width: 1_000)
        let wide = frame.pageLineWidth(forPenSize: 4)
        let narrow = frame.zoomed(by: 2).pageLineWidth(forPenSize: 4)
        #expect(abs(narrow - wide / 2) < 1e-9)
    }
}

@Suite("Trackpad sketch — strokes")
struct SketchStrokeTests {
    @Test("Jitter smaller than the threshold is dropped")
    func jitterIsIgnored() {
        var filter = SketchInputFilter(smoothing: 0, minimumDistance: 2)
        #expect(filter.accept(SketchPoint(x: 0, y: 0)) != nil)
        #expect(filter.accept(SketchPoint(x: 0.5, y: 0.5)) == nil)
        #expect(filter.accept(SketchPoint(x: 10, y: 0)) != nil)
    }

    @Test("Smoothing pulls a sample toward the previous one")
    func smoothingDampsSpikes() {
        var filter = SketchInputFilter(smoothing: 0.5, minimumDistance: 0)
        _ = filter.accept(SketchPoint(x: 0, y: 0))
        let damped = filter.accept(SketchPoint(x: 10, y: 0))
        #expect(damped == SketchPoint(x: 5, y: 0))
    }

    @Test("A curve passes through every sample and adds points between them")
    func curveInterpolatesThroughSamples() {
        let samples = [
            SketchPoint(x: 0, y: 0), SketchPoint(x: 10, y: 10),
            SketchPoint(x: 20, y: 0), SketchPoint(x: 30, y: 10),
        ]
        let curve = SketchCurve.interpolated(samples, stepsPerSegment: 4)
        #expect(curve.count == (samples.count - 1) * 4 + 1)
        for sample in samples {
            #expect(curve.contains(sample))
        }
        #expect(curve.first == samples.first)
        #expect(curve.last == samples.last)
    }

    @Test("A dot or a two-point line survives interpolation")
    func shortStrokesSurvive() {
        #expect(SketchCurve.interpolated([SketchPoint(x: 1, y: 1)], stepsPerSegment: 8) == [SketchPoint(x: 1, y: 1)])
        #expect(SketchCurve.interpolated([], stepsPerSegment: 8).isEmpty)
        let line = SketchCurve.interpolated([SketchPoint(x: 0, y: 0), SketchPoint(x: 8, y: 0)], stepsPerSegment: 4)
        #expect(line.count == 5)
        #expect(line.allSatisfy { $0.y == 0 })
    }

    @Test("Adding, undoing and clearing do not change the page they came from")
    func pageEditsAreImmutable() {
        let empty = SketchPage(size: SketchSize(width: 100, height: 100))
        let stroke = SketchStroke(width: 2, points: [SketchPoint(x: 1, y: 1)])
        let one = empty.adding(stroke)
        #expect(empty.strokes.isEmpty)
        #expect(one.strokes == [stroke])
        #expect(one.removingLastStroke().strokes.isEmpty)
        #expect(one.strokes.count == 1)
        #expect(one.cleared().strokes.isEmpty)
    }
}

@Suite("Trackpad sketch — saving")
struct SketchStorageTests {
    @Test("A sketch comes back exactly as it was saved")
    func roundTrips() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "atlas-sketch-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "pad.json")

        let document = SketchDocument.blank()
            .withPage(SketchDocument.blank().page.adding(
                SketchStroke(width: 3, points: [SketchPoint(x: 5, y: 6), SketchPoint(x: 7, y: 8)])
            ))
            .withViewport(SketchDocument.blank().viewport.zoomed(by: 1.5).panned(dx: 40, dy: 20))
            .withPenSize(6)

        try SketchDocumentFile.write(document, to: url)
        let loaded = try SketchDocumentFile.read(from: url)
        #expect(loaded == document)
    }

    @Test("No file yet means a blank page, not an error")
    func missingFileIsBlank() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "atlas-sketch-missing-\(UUID().uuidString).json")
        #expect(try SketchDocumentFile.read(from: url) == SketchDocument.blank())
    }

    @Test("A damaged file is reported, not silently replaced")
    func damagedFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "atlas-sketch-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try SketchDocumentFile.read(from: url) }
    }
}
