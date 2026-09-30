import Foundation

/// Pulls readable text out of PowerPoint and Word files.
///
/// Both are ZIP containers of XML. PowerPoint is the valuable one: each slide
/// is its own part, so slides survive as real, numbered units and a note can
/// cite "slide 7" and mean it. Word has no page boundaries in its markup —
/// pagination happens at render time — so a .docx becomes one block rather
/// than being cut into invented page numbers.
public enum OfficeTextExtractor {

    // MARK: - PowerPoint

    public static func extractPowerPoint(from url: URL) -> AttachmentTextExtractor.Result {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            return .init(text: "", note: "This PowerPoint file could not be opened.")
        }

        let slideParts = orderedSlideParts(in: archive)
        guard !slideParts.isEmpty else {
            return .init(text: "", note: "No slides could be read from this PowerPoint file.")
        }

        var pages: [AttachmentTextExtractor.Page] = []
        for (index, part) in slideParts.enumerated() {
            guard let data = try? archive.data(for: part) else { continue }
            var text = OOXMLText.parse(data, textElement: "a:t", paragraphElement: "a:p")

            // Speaker notes are often where the lecturer's own wording lives.
            if let notesPart = notesPart(for: part, in: archive),
               let notesData = try? archive.data(for: notesPart) {
                let notes = OOXMLText.parse(notesData, textElement: "a:t", paragraphElement: "a:p")
                if !notes.isEmpty { text += "\n\nSpeaker notes: \(notes)" }
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            pages.append(.init(number: index + 1, text: trimmed))
        }

        guard !pages.isEmpty else {
            return .init(
                text: "",
                note: "This PowerPoint file has \(slideParts.count) slides but no readable text — the content is probably images."
            )
        }
        return bounded(pages: pages, totalUnits: slideParts.count, noun: "slide")
    }

    /// Slide order comes from the presentation's own list, not from file names.
    /// `slide10.xml` sorts before `slide2.xml` lexicographically, and a deck
    /// whose slides were reordered keeps its original file numbers — either
    /// would put the wrong number on a citation.
    static func orderedSlideParts(in archive: ZipArchive) -> [String] {
        guard let presentation = try? archive.data(for: "ppt/presentation.xml"),
              let relationships = try? archive.data(for: "ppt/_rels/presentation.xml.rels") else {
            return numericallySortedSlideParts(in: archive)
        }

        let order = OOXMLText.attributeValues(presentation, element: "p:sldId", attribute: "r:id")
        let targets = OOXMLText.relationshipTargets(relationships)
        let parts = order.compactMap { id -> String? in
            guard let target = targets[id] else { return nil }
            let resolved = target.hasPrefix("/")
                ? String(target.dropFirst())
                : "ppt/" + target.replacingOccurrences(of: "../", with: "")
            return archive.contains(resolved) ? resolved : nil
        }
        return parts.isEmpty ? numericallySortedSlideParts(in: archive) : parts
    }

    private static func numericallySortedSlideParts(in archive: ZipArchive) -> [String] {
        archive.names(withPrefix: "ppt/slides/slide")
            .filter { $0.hasSuffix(".xml") }
            .sorted { slideNumber($0) < slideNumber($1) }
    }

    private static func slideNumber(_ name: String) -> Int {
        let digits = name.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private static func notesPart(for slidePart: String, in archive: ZipArchive) -> String? {
        let fileName = slidePart.split(separator: "/").last.map(String.init) ?? slidePart
        let relsPath = "ppt/slides/_rels/\(fileName).rels"
        guard let data = try? archive.data(for: relsPath) else { return nil }
        let targets = OOXMLText.relationshipTargets(data, typeSuffix: "notesSlide")
        guard let target = targets.values.first else { return nil }
        let resolved = "ppt/" + target.replacingOccurrences(of: "../", with: "")
        return archive.contains(resolved) ? resolved : nil
    }

    // MARK: - Word

    public static func extractWord(from url: URL) -> AttachmentTextExtractor.Result {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            return .init(text: "", note: "This Word file could not be opened.")
        }
        guard let document = try? archive.data(for: "word/document.xml") else {
            return .init(text: "", note: "No readable document part was found in this Word file.")
        }

        let text = OOXMLText
            .parse(document, textElement: "w:t", paragraphElement: "w:p")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .init(text: "", note: "This Word file has no readable text — the content is probably images.")
        }

        // One block, deliberately: Word carries no page boundaries, and a
        // citation to an invented page number is worse than no number.
        guard text.count <= AttachmentTextExtractor.maximumCharacters else {
            let kept = String(text.prefix(AttachmentTextExtractor.maximumCharacters))
            return .init(
                text: kept,
                pages: [.init(number: 1, text: kept)],
                note: "Only the first \(AttachmentTextExtractor.maximumCharacters) characters were read; the rest was too long to store."
            )
        }
        return .init(text: text, pages: [.init(number: 1, text: text)], note: nil)
    }

    // MARK: - Shared

    private static func bounded(
        pages: [AttachmentTextExtractor.Page],
        totalUnits: Int,
        noun: String
    ) -> AttachmentTextExtractor.Result {
        var kept: [AttachmentTextExtractor.Page] = []
        var used = 0
        for page in pages {
            let cost = page.text.count + 2
            guard used + cost <= AttachmentTextExtractor.maximumCharacters else { break }
            kept.append(page)
            used += cost
        }
        if kept.isEmpty, let first = pages.first {
            kept = [.init(number: first.number, text: String(first.text.prefix(AttachmentTextExtractor.maximumCharacters)))]
        }

        let joined = kept.map { "[\(noun) \($0.number)] \($0.text)" }.joined(separator: "\n\n")
        let note = kept.count < pages.count
            ? "Read \(noun)s \(kept.first?.number ?? 1)–\(kept.last?.number ?? 1) of \(totalUnits); the rest was too long to store."
            : nil
        return .init(text: joined, pages: kept, note: note)
    }
}

/// A small XML reader for the two shapes OOXML text takes.
enum OOXMLText {
    /// Joins the text runs inside each paragraph, one paragraph per line.
    static func parse(_ data: Data, textElement: String, paragraphElement: String) -> String {
        let delegate = TextCollector(textElement: textElement, paragraphElement: paragraphElement)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return delegate.result }
        return delegate.result
    }

    /// Ordered attribute values, used for the slide list.
    static func attributeValues(_ data: Data, element: String, attribute: String) -> [String] {
        let delegate = AttributeCollector(element: element, attribute: attribute)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.values
    }

    /// Relationship id → target, optionally filtered by relationship type.
    static func relationshipTargets(_ data: Data, typeSuffix: String? = nil) -> [String: String] {
        let delegate = RelationshipCollector(typeSuffix: typeSuffix)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.targets
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        private let textElement: String
        private let paragraphElement: String
        private var insideText = false
        private var paragraph = ""
        private var paragraphs: [String] = []

        init(textElement: String, paragraphElement: String) {
            self.textElement = textElement
            self.paragraphElement = paragraphElement
        }

        var result: String {
            (paragraphs + [paragraph])
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            switch elementName {
            case textElement: insideText = true
            case "w:tab": paragraph += "\t"
            case "w:br", "a:br": paragraph += "\n"
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard insideText else { return }
            paragraph += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            if elementName == textElement { insideText = false }
            if elementName == paragraphElement {
                paragraphs.append(paragraph)
                paragraph = ""
            }
        }
    }

    private final class AttributeCollector: NSObject, XMLParserDelegate {
        private let element: String
        private let attribute: String
        private(set) var values: [String] = []

        init(element: String, attribute: String) {
            self.element = element
            self.attribute = attribute
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard elementName == element, let value = attributes[attribute] else { return }
            values.append(value)
        }
    }

    private final class RelationshipCollector: NSObject, XMLParserDelegate {
        private let typeSuffix: String?
        private(set) var targets: [String: String] = [:]

        init(typeSuffix: String?) { self.typeSuffix = typeSuffix }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard elementName == "Relationship",
                  let id = attributes["Id"],
                  let target = attributes["Target"] else { return }
            if let typeSuffix {
                guard attributes["Type"]?.hasSuffix(typeSuffix) == true else { return }
            }
            targets[id] = target
        }
    }
}
