import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Pulls readable text out of an attached file.
///
/// Extraction is deliberately conservative: a format it cannot read returns a
/// reason rather than an empty string, so an attachment that contributes
/// nothing says why instead of looking like it worked.
public enum AttachmentTextExtractor {
    public static let maximumCharacters = 400_000

    /// One page of an attached document, kept separate so a note can point at
    /// "slide 7" rather than at the file as a whole.
    public struct Page: Codable, Hashable, Sendable {
        public let number: Int
        public let text: String

        public init(number: Int, text: String) {
            self.number = number
            self.text = text
        }
    }

    public struct Result: Sendable, Equatable {
        public let text: String
        public let pages: [Page]
        public let note: String?

        public init(text: String, pages: [Page] = [], note: String?) {
            self.text = text
            self.pages = pages
            self.note = note
        }
    }

    public static let readableExtensions: Set<String> = [
        "pdf", "pptx", "docx", "txt", "text", "md", "markdown", "rtf", "csv", "tsv", "json", "log"
    ]

    public static func isReadable(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }

    public static func extract(from url: URL) -> Result {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return extractPDF(url)
        case "pptx":
            return OfficeTextExtractor.extractPowerPoint(from: url)
        case "docx":
            return OfficeTextExtractor.extractWord(from: url)
        case "rtf":
            return extractRTF(url)
        case "txt", "text", "md", "markdown", "csv", "tsv", "json", "log":
            return extractPlainText(url)
        default:
            return Result(
                text: "",
                note: "Atlas cannot read text from a .\(url.pathExtension.lowercased()) file. The file is still attached."
            )
        }
    }

    private static func extractPDF(_ url: URL) -> Result {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            return Result(text: "", note: "This PDF could not be opened.")
        }
        // Page boundaries are preserved rather than flattened: they are the
        // only thing that lets a note cite "slide 7" instead of "the slides".
        var pages: [Page] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            pages.append(Page(number: index + 1, text: text))
        }
        guard !pages.isEmpty else {
            return Result(
                text: "",
                note: "This PDF has no selectable text — it is probably scanned images. Nothing could be read from it."
            )
        }
        return bounded(pages: pages, totalPages: document.pageCount)
        #else
        return Result(text: "", note: "PDF text extraction is unavailable on this platform.")
        #endif
    }

    private static func extractRTF(_ url: URL) -> Result {
        guard let data = try? Data(contentsOf: url),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ) else {
            return Result(text: "", note: "This rich text file could not be read.")
        }
        return bounded(attributed.string)
    }

    private static func extractPlainText(_ url: URL) -> Result {
        // Foundation reads a byte-order mark or declared encoding correctly.
        var detected = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detected) {
            return bounded(text)
        }
        // Then single-byte fallbacks. UTF-16 is deliberately absent: without a
        // BOM it decodes arbitrary bytes into plausible-looking nonsense rather
        // than failing, which would hide a perfectly readable Latin-1 file.
        for encoding in [String.Encoding.utf8, .isoLatin1, .macOSRoman] {
            if let text = try? String(contentsOf: url, encoding: encoding) {
                return bounded(text)
            }
        }
        return Result(text: "", note: "This file's text encoding could not be recognised.")
    }

    /// A file with no page structure is still one page, so every attachment
    /// can be referenced the same way.
    private static func bounded(_ text: String) -> Result {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > maximumCharacters else {
            return Result(text: clean, pages: [Page(number: 1, text: clean)], note: nil)
        }
        let kept = String(clean.prefix(maximumCharacters))
        return Result(
            text: kept,
            pages: [Page(number: 1, text: kept)],
            note: "Only the first \(maximumCharacters) characters were read; the rest was too long to store."
        )
    }

    /// Keeps whole pages, dropping from the end once the cap is reached, so a
    /// page reference always points at text that is actually stored.
    private static func bounded(pages: [Page], totalPages: Int) -> Result {
        var kept: [Page] = []
        var used = 0
        for page in pages {
            let cost = page.text.count + 2
            guard used + cost <= maximumCharacters else { break }
            kept.append(page)
            used += cost
        }

        let truncated = kept.count < pages.count
        if kept.isEmpty, let first = pages.first {
            kept = [Page(number: first.number, text: String(first.text.prefix(maximumCharacters)))]
        }

        let joined = kept.map { "[p. \($0.number)] \($0.text)" }.joined(separator: "\n\n")
        let note = truncated
            ? "Read pages \(kept.first?.number ?? 1)–\(kept.last?.number ?? 1) of \(totalPages); the rest was too long to store."
            : nil
        return Result(text: joined, pages: kept, note: note)
    }
}
