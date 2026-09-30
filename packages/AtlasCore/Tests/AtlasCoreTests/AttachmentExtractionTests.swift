import Foundation
import Testing
@testable import AtlasCore

@Suite("Attachment text extraction")
struct AttachmentExtractionTests {
    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "atlas-attachment-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url
    }

    @Test("Plain text and Markdown are read as-is")
    func plainTextIsRead() throws {
        let url = try temporaryFile(named: "reading.md", contents: Data("# Week 3\n\nB-trees give logarithmic lookups.".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.contains("B-trees give logarithmic lookups."))
        #expect(result.note == nil)
    }

    @Test("A file in a non-UTF8 encoding still reads rather than failing")
    func encodingFallbackWorks() throws {
        let latin1 = "Café selectivity".data(using: .isoLatin1)!
        let url = try temporaryFile(named: "notes.txt", contents: latin1)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.contains("selectivity"))
    }

    @Test("An unsupported format says so instead of contributing silence")
    func unsupportedFormatsExplainThemselves() throws {
        // Keynote is a genuinely unsupported container; .pptx and .docx are
        // read now, so they no longer belong in this test.
        let url = try temporaryFile(named: "slides.key", contents: Data("binary".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.isEmpty)
        #expect(result.note?.contains(".key") == true)
        #expect(AttachmentTextExtractor.isReadable(url) == false)
    }

    @Test("A file longer than the cap is truncated and says it was")
    func longFilesAreTruncated() throws {
        let long = String(repeating: "selectivity ", count: 60_000)
        let url = try temporaryFile(named: "textbook.txt", contents: Data(long.utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.count == AttachmentTextExtractor.maximumCharacters)
        #expect(result.note?.contains("too long") == true)
    }

    @Test("Readable formats are recognised before a file is copied in")
    func readableFormatsAreListed() {
        for name in ["a.pdf", "b.txt", "c.md", "d.rtf", "e.csv", "f.json", "g.pptx", "h.docx"] {
            #expect(AttachmentTextExtractor.isReadable(URL(fileURLWithPath: name)))
        }
        // The pre-OOXML formats are a different, undocumented binary container.
        for name in ["i.key", "j.zip", "k.ppt", "l.doc", "m.pages"] {
            #expect(!AttachmentTextExtractor.isReadable(URL(fileURLWithPath: name)))
        }
    }
}

@Suite("Attachments in note writing")
struct AttachmentStructuringTests {
    @Test("Attached material is chunked at the model's budget, per document")
    func attachmentsAreChunked() {
        let service = LectureStructuringService(client: BudgetedStubClient())
        let chunks = service.attachmentChunks(for: [
            LectureAttachmentText(name: "Slides.pdf", text: String(repeating: "a", count: 2_500)),
            LectureAttachmentText(name: "Reading.txt", text: String(repeating: "b", count: 900)),
            LectureAttachmentText(name: "Empty.txt", text: "short")
        ])

        let names = Set(chunks.map(\.documentName))
        #expect(names == ["Slides.pdf", "Reading.txt"])
        #expect(chunks.filter { $0.documentName == "Slides.pdf" }.count >= 2)
        // Too short to be worth a model call at all.
        #expect(!names.contains("Empty.txt"))
    }

    @Test("Each slice carries the pages it came from, so a citation can be checked")
    func chunksCarryTheirPages() {
        let service = LectureStructuringService(client: BudgetedStubClient())
        let slides = LectureAttachmentText(
            name: "Week 3 slides.pdf",
            text: "ignored",
            pages: (1...6).map { AttachmentTextExtractor.Page(number: $0, text: String(repeating: "x", count: 400)) },
            pageNoun: "slide"
        )

        let chunks = service.attachmentChunks(for: [slides])
        #expect(chunks.count > 1)
        #expect(chunks.first?.firstPage == 1)
        #expect(chunks.last?.lastPage == 6)
        // Pages run in order and nothing is skipped between slices.
        for (earlier, later) in zip(chunks, chunks.dropFirst()) {
            #expect(later.firstPage == earlier.lastPage + 1)
        }
        // The page number is in the text the model reads, and in its label.
        #expect(chunks.first?.text.contains("[slide 1]") == true)
        #expect(chunks.first?.pageLabel.contains("slide") == true)
    }

    @Test("A single page too long for one request keeps its own number on both halves")
    func oversizedPagesKeepTheirNumber() {
        let service = LectureStructuringService(client: BudgetedStubClient())
        let reading = LectureAttachmentText(
            name: "Chapter 4.pdf",
            text: "ignored",
            pages: [AttachmentTextExtractor.Page(number: 12, text: String(repeating: "y", count: 3_000))],
            pageNoun: "page"
        )

        let chunks = service.attachmentChunks(for: [reading])
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.firstPage == 12 && $0.lastPage == 12 })
    }

    @Test("The lecture leads and attachments fill the gaps it left")
    func lectureWinsOverSlides() {
        let fromLecture = LectureStructure(
            title: "Week 3",
            summary: "What the lecturer said.",
            keyPoints: ["Indexes cost writes"]
        )
        let fromSlides = LectureStructure(
            title: "Lecture 9 Slides",
            courseCode: "DS1800",
            summary: "What the slides say.",
            keyPoints: ["Indexes cost writes", "B-trees are balanced"],
            glossary: [LectureGlossaryTerm(term: "B-tree", shortDefinition: "A balanced tree.", deepExplanation: "")]
        )

        let merged = fromLecture.merging(fromSlides)
        #expect(merged.title == "Week 3")
        // A field the lecture left empty is filled from the slides.
        #expect(merged.courseCode == "DS1800")
        #expect(merged.keyPoints == ["Indexes cost writes", "B-trees are balanced"])
        #expect(merged.glossary.count == 1)
    }
}

@Suite("Citable attachments in notes")
struct AttachmentCitationTests {
    private func context(with attachments: [LectureAttachmentText]) -> LectureNoteContext {
        LectureNoteContext(
            lectureID: "l1",
            recordedAt: Date(timeIntervalSince1970: 1_757_000_000),
            durationSeconds: 600,
            courseTitle: "DS 1800",
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            segments: [AtlasLectureSegment(start: 0, end: 20, text: "Indexes cost writes.")],
            transcriptText: "Indexes cost writes.",
            attachments: attachments
        )
    }

    @Test("Slides appear as numbered blocks a citation can be checked against")
    func slidesRenderNumbered() {
        let slides = LectureAttachmentText(
            name: "Week 3 slides.pdf",
            text: "ignored",
            pages: [
                AttachmentTextExtractor.Page(number: 1, text: "Why indexes exist"),
                AttachmentTextExtractor.Page(number: 2, text: "Selectivity = matched / total")
            ],
            pageNoun: "slide"
        )
        let depth = LectureNoteBuilder.depthNote(
            structure: LectureStructure(summary: "Indexes."),
            context: context(with: [slides]),
            studyTitle: "Week 3"
        )

        #expect(depth.markdown.contains("**Slide 1.** Why indexes exist"))
        #expect(depth.markdown.contains("**Slide 2.** Selectivity = matched / total"))
        // The contract tells the reader the numbers are checkable.
        #expect(depth.markdown.contains("points at the numbered block below"))
    }

    @Test("A reading with no page structure renders whole, without a page number it does not have")
    func unpagedFilesStillRender() {
        let reading = LectureAttachmentText(name: "notes.txt", text: "Plain text reading material here.")
        let depth = LectureNoteBuilder.depthNote(
            structure: LectureStructure(summary: "x"),
            context: context(with: [reading]),
            studyTitle: "s"
        )
        #expect(depth.markdown.contains("Plain text reading material here."))
        #expect(!depth.markdown.contains("**Page 1.**"))
    }

    @Test("Long material drops whole pages rather than cutting one in half")
    func truncationKeepsPagesWhole() {
        let pages = (1...200).map {
            AttachmentTextExtractor.Page(number: $0, text: String(repeating: "z", count: 1_000))
        }
        let huge = LectureAttachmentText(name: "Textbook.pdf", text: "ignored", pages: pages, pageNoun: "page")
        let depth = LectureNoteBuilder.depthNote(
            structure: LectureStructure(summary: "x"),
            context: context(with: [huge]),
            studyTitle: "s"
        )

        #expect(depth.markdown.contains("were too long to include here"))
        // Whatever survived is a complete page, never a half one.
        let kept = depth.markdown.components(separatedBy: "**Page ").dropFirst()
        for block in kept where block.contains("z") {
            #expect(block.contains(String(repeating: "z", count: 1_000)))
        }
    }
}

private struct BudgetedStubClient: LectureModelClient {
    let identifier = "Stub"
    var chunkCharacterBudget: Int { 1_000 }
    func isReachable() async -> Bool { true }
    func complete(system: String, user: String) async throws -> String { "{}" }
}
