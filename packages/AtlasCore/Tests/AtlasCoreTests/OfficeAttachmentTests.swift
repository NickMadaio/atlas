import Foundation
import Testing
@testable import AtlasCore

/// Builds a ZIP by hand, with entries stored rather than deflated, so the
/// container parsing is exercised without needing a binary fixture in the repo.
private struct ZipBuilder {
    private var localParts = Data()
    private var directory = Data()
    private var count = 0

    private static func uint16(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func uint32(_ value: Int) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    mutating func add(_ name: String, _ contents: String) {
        let nameData = Data(name.utf8)
        let body = Data(contents.utf8)
        let offset = localParts.count

        var local = Data()
        local.append(Self.uint32(0x0403_4b50))
        local.append(Self.uint16(20))
        local.append(Self.uint16(0))
        local.append(Self.uint16(0))          // stored
        local.append(Self.uint16(0))
        local.append(Self.uint16(0))
        local.append(Self.uint32(0))          // crc, unchecked by the reader
        local.append(Self.uint32(body.count))
        local.append(Self.uint32(body.count))
        local.append(Self.uint16(nameData.count))
        local.append(Self.uint16(0))
        local.append(nameData)
        local.append(body)
        localParts.append(local)

        var entry = Data()
        entry.append(Self.uint32(0x0201_4b50))
        entry.append(Self.uint16(20))
        entry.append(Self.uint16(20))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint32(0))
        entry.append(Self.uint32(body.count))
        entry.append(Self.uint32(body.count))
        entry.append(Self.uint16(nameData.count))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint16(0))
        entry.append(Self.uint32(0))
        entry.append(Self.uint32(offset))
        entry.append(nameData)
        directory.append(entry)
        count += 1
    }

    func build() -> Data {
        var output = localParts
        let directoryOffset = output.count
        output.append(directory)
        output.append(Self.uint32(0x0605_4b50))
        output.append(Self.uint16(0))
        output.append(Self.uint16(0))
        output.append(Self.uint16(count))
        output.append(Self.uint16(count))
        output.append(Self.uint32(directory.count))
        output.append(Self.uint32(directoryOffset))
        output.append(Self.uint16(0))
        return output
    }
}

private func write(_ data: Data, named name: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "atlas-office-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    try data.write(to: url)
    return url
}

private func slideXML(_ text: String) -> String {
    """
    <p:sld><p:cSld><p:spTree><p:sp><p:txBody>
    <a:p><a:r><a:t>\(text)</a:t></a:r></a:p>
    </p:txBody></p:sp></p:spTree></p:cSld></p:sld>
    """
}

@Suite("PowerPoint and Word attachments")
struct OfficeAttachmentTests {

    @Test("A ZIP's named entries can be read back")
    func zipReadsEntries() throws {
        var builder = ZipBuilder()
        builder.add("word/document.xml", "<w:document/>")
        builder.add("[Content_Types].xml", "<Types/>")

        let archive = try ZipArchive(data: builder.build())
        #expect(archive.contains("word/document.xml"))
        #expect(!archive.contains("ppt/presentation.xml"))
        let data = try archive.data(for: "word/document.xml")
        #expect(String(decoding: data, as: UTF8.self) == "<w:document/>")
    }

    @Test("Something that is not a ZIP is refused rather than misread")
    func zipRejectsRubbish() {
        #expect(throws: (any Error).self) {
            _ = try ZipArchive(data: Data(repeating: 0x41, count: 512))
        }
    }

    @Test("Slide order follows the presentation, not the file names")
    func slideOrderFollowsThePresentation() throws {
        var builder = ZipBuilder()
        // The deck presents slide2 first — reordered after authoring, which is
        // exactly when file names stop matching slide numbers.
        builder.add("ppt/presentation.xml", """
        <p:presentation><p:sldIdLst>
        <p:sldId id="256" r:id="rId3"/>
        <p:sldId id="257" r:id="rId2"/>
        </p:sldIdLst></p:presentation>
        """)
        builder.add("ppt/_rels/presentation.xml.rels", """
        <Relationships>
        <Relationship Id="rId2" Type="http://x/slide" Target="slides/slide1.xml"/>
        <Relationship Id="rId3" Type="http://x/slide" Target="slides/slide2.xml"/>
        </Relationships>
        """)
        builder.add("ppt/slides/slide1.xml", slideXML("Costs of indexes"))
        builder.add("ppt/slides/slide2.xml", slideXML("What an index is"))

        let url = try write(builder.build(), named: "deck.pptx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.pages.count == 2)
        #expect(result.pages.first?.number == 1)
        #expect(result.pages.first?.text.contains("What an index is") == true)
        #expect(result.pages.last?.text.contains("Costs of indexes") == true)
        #expect(result.text.contains("[slide 1]"))
    }

    @Test("Speaker notes are pulled in with their slide")
    func speakerNotesAreIncluded() throws {
        var builder = ZipBuilder()
        builder.add("ppt/slides/slide1.xml", slideXML("Selectivity"))
        builder.add("ppt/slides/_rels/slide1.xml.rels", """
        <Relationships>
        <Relationship Id="rId1" Type="http://x/notesSlide" Target="../notesSlides/notesSlide1.xml"/>
        </Relationships>
        """)
        builder.add("ppt/notesSlides/notesSlide1.xml", slideXML("Remember to mention the optimizer."))

        let url = try write(builder.build(), named: "deck.pptx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.pages.first?.text.contains("Selectivity") == true)
        #expect(result.pages.first?.text.contains("Speaker notes: Remember to mention the optimizer.") == true)
    }

    @Test("A deck with no readable text says so instead of looking empty")
    func imageOnlyDeckExplainsItself() throws {
        var builder = ZipBuilder()
        builder.add("ppt/slides/slide1.xml", "<p:sld><p:cSld><p:spTree/></p:cSld></p:sld>")

        let url = try write(builder.build(), named: "scans.pptx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.isEmpty)
        #expect(result.note?.contains("no readable text") == true)
    }

    @Test("Word paragraphs survive and split runs are rejoined")
    func wordTextIsRead() throws {
        var builder = ZipBuilder()
        builder.add("word/document.xml", """
        <w:document><w:body>
        <w:p><w:r><w:t>DS 1800 Syllabus</w:t></w:r></w:p>
        <w:p><w:r><w:t>Assessment: two presentations,</w:t></w:r><w:r><w:t> one final project.</w:t></w:r></w:p>
        </w:body></w:document>
        """)

        let url = try write(builder.build(), named: "syllabus.docx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        // Runs inside one paragraph become one sentence, not two fragments.
        #expect(result.text.contains("Assessment: two presentations, one final project."))
        #expect(result.text.contains("DS 1800 Syllabus"))
        // Word carries no page boundaries, so it is one block rather than
        // invented page numbers.
        #expect(result.pages.count == 1)
    }

    @Test("A Word file with no document part is reported, not silently empty")
    func brokenWordFileExplainsItself() throws {
        var builder = ZipBuilder()
        builder.add("[Content_Types].xml", "<Types/>")

        let url = try write(builder.build(), named: "broken.docx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = AttachmentTextExtractor.extract(from: url)
        #expect(result.text.isEmpty)
        #expect(result.note?.contains("document part") == true)
    }

    @Test("Both formats are offered before a file is copied in")
    func formatsAreRecognised() {
        #expect(AttachmentTextExtractor.isReadable(URL(fileURLWithPath: "deck.pptx")))
        #expect(AttachmentTextExtractor.isReadable(URL(fileURLWithPath: "notes.docx")))
        #expect(!AttachmentTextExtractor.isReadable(URL(fileURLWithPath: "old.ppt")))
        #expect(!AttachmentTextExtractor.isReadable(URL(fileURLWithPath: "old.doc")))
    }

    @Test("A deck is numbered in slides and a document is not numbered at all")
    func nounFollowsTheFileType() {
        let deck = AtlasAttachmentSnapshot(
            id: "1", lectureID: "l", fileName: "abc.pptx", displayName: "Week 3.pptx",
            extractedText: "x", pages: [.init(number: 1, text: "a"), .init(number: 2, text: "b")],
            byteSize: 10, addedAt: .now, extractionNote: nil
        )
        #expect(deck.pageNoun == "slide")
        #expect(deck.pageLabel == "2 slides")

        let document = AtlasAttachmentSnapshot(
            id: "2", lectureID: "l", fileName: "def.docx", displayName: "Syllabus.docx",
            extractedText: "x", pages: [.init(number: 1, text: "a")],
            byteSize: 10, addedAt: .now, extractionNote: nil
        )
        #expect(document.pageNoun == "page")
        // One block is not labelled with a page number it does not have.
        #expect(document.pageLabel == nil)
    }
}
