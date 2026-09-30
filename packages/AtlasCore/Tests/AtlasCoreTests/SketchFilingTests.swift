import Foundation
import Testing
@testable import AtlasCore

@Suite("Trackpad sketch — filing into notes")
struct SketchFilingTests {
    private let id = UUID(uuidString: "6F9A2C1E-0B7D-4E55-9C3A-1D2E3F405162")!

    @Test("An embed line round-trips to the sketch it names")
    func embedRoundTrips() {
        let line = SketchEmbed.markdown(for: id)
        #expect(SketchEmbed.sketchID(inLine: line) == id)
        #expect(SketchEmbed.sketchID(inLine: "  \(line)  ") == id)
        #expect(SketchEmbed.sketchID(inLine: "See \(line)") == nil)
        #expect(SketchEmbed.sketchID(inLine: "![Sketch](atlas-sketch://not-a-uuid)") == nil)
    }

    @Test("A sketch line is its own block, and ends the paragraph above it")
    func parsesAsBlock() {
        let blocks = MarkdownBlockParser.parse("Some text\n\(SketchEmbed.markdown(for: id))\nMore text")
        #expect(blocks.count == 3)
        guard case let .sketch(parsed) = blocks[1] else {
            Issue.record("Expected a sketch block, got \(blocks[1])")
            return
        }
        #expect(parsed == id)
    }

    @Test("Adding to a note without a Sketches section appends one at the end")
    func appendsSection() {
        let body = "## Outline\n\n- One\n- Two"
        let filed = SketchEmbed.appending(id, caption: "Krebs cycle", to: body)
        #expect(filed.hasPrefix(body))
        #expect(filed.hasSuffix("## Sketches\n\n**Krebs cycle**\n\n\(SketchEmbed.markdown(for: id))\n"))
    }

    @Test("A second sketch joins the existing Sketches section, before the next heading")
    func joinsExistingSection() {
        let first = UUID()
        let body = "## Sketches\n\n\(SketchEmbed.markdown(for: first))\n\n## Quiz\n\n1. Why?"
        let filed = SketchEmbed.appending(id, caption: "", to: body)
        let sketchesRange = filed.range(of: "## Sketches")!
        let quizRange = filed.range(of: "## Quiz")!
        let newRange = filed.range(of: SketchEmbed.markdown(for: id))!
        #expect(newRange.lowerBound > sketchesRange.upperBound)
        #expect(newRange.upperBound < quizRange.lowerBound)
        #expect(filed.components(separatedBy: "## Sketches").count == 2)
        #expect(filed.hasSuffix("1. Why?"))
    }

    @Test("A sketch is framed around what was drawn, not the whole page")
    func boundsHugTheInk() {
        let page = SketchPage(size: SketchSize(width: 6_000, height: 4_000))
            .adding(SketchStroke(width: 10, points: [SketchPoint(x: 1_000, y: 500), SketchPoint(x: 1_400, y: 700)]))
            .adding(SketchStroke(width: 10, points: [SketchPoint(x: 1_200, y: 900)]))
        let bounds = page.inkBounds(padding: 20)!
        #expect(bounds.minX == 1_000 - 5 - 20)
        #expect(bounds.minY == 500 - 5 - 20)
        #expect(bounds.maxX == 1_400 + 5 + 20)
        #expect(bounds.maxY == 900 + 5 + 20)
        #expect(SketchPage(size: page.size).inkBounds(padding: 20) == nil)
    }

    @Test("Reading a sketch a note points at fails loudly if the file is gone")
    func missingSavedSketchThrows() {
        let url = FileManager.default.temporaryDirectory.appending(path: "atlas-sketch-gone-\(UUID().uuidString).json")
        #expect(throws: SketchDocumentFile.Missing.self) { try SketchDocumentFile.readSaved(from: url) }
    }
}
