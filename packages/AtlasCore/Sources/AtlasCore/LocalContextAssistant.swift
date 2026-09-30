import Foundation

public struct AtlasLocalContext: Sendable {
    public let collection: AtlasCollectionSnapshot?
    public let document: AtlasDocumentSnapshot?
    public let documents: [AtlasDocumentSnapshot]

    public init(
        collection: AtlasCollectionSnapshot?,
        document: AtlasDocumentSnapshot?,
        documents: [AtlasDocumentSnapshot]
    ) {
        self.collection = collection
        self.document = document
        self.documents = Array(documents.prefix(200))
    }

    public var id: String {
        if let document { return "document:\(document.id):\(document.updatedAt.timeIntervalSince1970)" }
        if let collection { return "collection:\(collection.id):\(documents.count)" }
        return "library:\(documents.count)"
    }

    public var title: String {
        document?.title ?? collection?.title ?? "All notes"
    }

    public var scopeLabel: String {
        if document != nil { return "THIS NOTE" }
        if collection != nil { return "THIS COLLECTION" }
        return "YOUR LIBRARY"
    }
}

public struct AtlasLocalSource: Identifiable, Hashable, Sendable {
    public let id: String
    public let documentID: String
    public let documentTitle: String
    public let sectionID: String
    public let sectionTitle: String

    public init(documentID: String, documentTitle: String, sectionID: String, sectionTitle: String) {
        id = "\(documentID):\(sectionID)"
        self.documentID = documentID
        self.documentTitle = documentTitle
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
    }
}

public struct AtlasLocalAnswer: Equatable, Sendable {
    public let title: String
    public let body: String
    public let sources: [AtlasLocalSource]

    public init(title: String, body: String, sources: [AtlasLocalSource] = []) {
        self.title = title
        self.body = body
        self.sources = sources
    }
}

/// A bounded, deterministic helper for the note or collection already visible
/// in Atlas. It performs no network requests and never treats note text as an
/// instruction. Results are extractive and name their source sections.
public enum AtlasLocalAssistant {
    public static let maximumQuestionLength = 240

    public static func suggestions(for context: AtlasLocalContext) -> [String] {
        if context.document != nil {
            return ["Give me the key points", "What should I do next?", "Find an important detail"]
        }
        if context.collection != nil {
            return ["Summarize this collection", "What should I do next?", "What topics are covered?"]
        }
        return ["Summarize my library", "What should I do next?", "What topics are covered?"]
    }

    public static func welcome(for context: AtlasLocalContext) -> AtlasLocalAnswer {
        let passages = passages(in: context)
        if let document = context.document {
            let description = document.summary.isEmpty
                ? firstUsefulLine(in: document.bodyMarkdown) ?? "This note has no written overview yet."
                : document.summary
            return AtlasLocalAnswer(
                title: "About this note",
                body: "\(description)\n\n\(passages.count) sections are available for local lookup."
            )
        }

        let noteCount = context.documents.count
        let sectionCount = passages.count
        let label = context.collection == nil ? "your library" : "this collection"
        return AtlasLocalAnswer(
            title: "Ready to help locally",
            body: "I can search and extract information from \(label): \(noteCount) notes and \(sectionCount) sections. Nothing is sent off this device."
        )
    }

    public static func answer(_ rawQuestion: String, in context: AtlasLocalContext) -> AtlasLocalAnswer {
        let question = String(rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumQuestionLength))
        guard !question.isEmpty else {
            return AtlasLocalAnswer(title: "Ask a question", body: "Type a question or choose one of the suggestions above.")
        }

        let lowered = question.lowercased()
        if containsAny(lowered, ["next", "action", "todo", "to-do", "should i", "do now"]) {
            return actionAnswer(in: context)
        }
        if containsAny(lowered, ["summary", "summarize", "overview", "key point", "main point"]) {
            return summaryAnswer(in: context)
        }
        if containsAny(lowered, ["topic", "covered", "inside", "contain"]) {
            return topicsAnswer(in: context)
        }

        let terms = tokens(in: question)
        guard !terms.isEmpty else {
            return AtlasLocalAnswer(
                title: "Try a more specific question",
                body: "Include a topic, person, deadline, decision, or phrase that appears in the current context."
            )
        }

        let matches = passages(in: context)
            .map { passage in (passage, score(passage, for: terms)) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 { return $0.0.source.id < $1.0.source.id }
                return $0.1 > $1.1
            }
            .prefix(3)

        guard !matches.isEmpty else {
            return AtlasLocalAnswer(
                title: "I couldn't find that here",
                body: "No matching passage appears in \(context.title). Try a name, heading, or shorter phrase. I only answer from the current local context."
            )
        }

        let selected = matches.map(\.0)
        let body = selected.map { "• \($0.source.documentTitle) — \($0.source.sectionTitle): \(snippet(from: $0.text, matching: terms))" }
            .joined(separator: "\n")
        return AtlasLocalAnswer(title: "Found in \(context.title)", body: body, sources: selected.map(\.source))
    }

    private static func summaryAnswer(in context: AtlasLocalContext) -> AtlasLocalAnswer {
        let selected = passages(in: context).prefix(5)
        guard !selected.isEmpty else {
            return AtlasLocalAnswer(title: "Nothing to summarize yet", body: "Add content to this note or collection, then ask again.")
        }
        let body = selected.map { "• \($0.source.sectionTitle): \(snippet(from: $0.text, matching: []))" }
            .joined(separator: "\n")
        return AtlasLocalAnswer(title: "Key points", body: body, sources: selected.map(\.source))
    }

    private static func actionAnswer(in context: AtlasLocalContext) -> AtlasLocalAnswer {
        let actionWords = ["apply", "build", "confirm", "contact", "create", "finish", "prepare", "review", "schedule", "send", "start", "update", "verify"]
        var found: [(String, AtlasLocalSource)] = []
        for passage in passages(in: context) {
            for rawLine in passage.text.components(separatedBy: .newlines) {
                let line = clean(rawLine)
                let lowered = line.lowercased()
                let isTask = rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]")
                let startsWithAction = actionWords.contains { lowered.hasPrefix($0 + " ") }
                let hasDirective = lowered.contains("should ") || lowered.contains("next step") || lowered.contains("need to")
                if line.count >= 8, isTask || startsWithAction || hasDirective {
                    found.append((String(line.prefix(220)), passage.source))
                }
                if found.count == 6 { break }
            }
            if found.count == 6 { break }
        }

        guard !found.isEmpty else {
            return AtlasLocalAnswer(
                title: "No explicit actions found",
                body: "This context does not contain unchecked tasks or clear next-step language. Try asking about a specific topic instead."
            )
        }
        return AtlasLocalAnswer(
            title: "Practical next steps",
            body: found.map { "• \($0.0)" }.joined(separator: "\n"),
            sources: uniqueSources(found.map(\.1))
        )
    }

    private static func topicsAnswer(in context: AtlasLocalContext) -> AtlasLocalAnswer {
        let all = passages(in: context)
        guard !all.isEmpty else {
            return AtlasLocalAnswer(title: "No topics yet", body: "This context does not contain any written sections.")
        }
        let grouped = Dictionary(grouping: all, by: { $0.source.documentTitle })
        let body = grouped.keys.sorted().prefix(8).map { title in
            let headings = grouped[title, default: []].prefix(5).map { $0.source.sectionTitle }.joined(separator: ", ")
            return "• \(title): \(headings)"
        }.joined(separator: "\n")
        return AtlasLocalAnswer(title: "Topics in \(context.title)", body: body, sources: uniqueSources(all.map(\.source)))
    }

    private struct Passage {
        let text: String
        let source: AtlasLocalSource
    }

    private static func passages(in context: AtlasLocalContext) -> [Passage] {
        let documents = context.document.map { [$0] } ?? context.documents
        return documents.prefix(200).flatMap { document in
            MarkdownSections.parse(String(document.bodyMarkdown.prefix(80_000))).prefix(100).map { section in
                Passage(
                    text: section.markdown,
                    source: AtlasLocalSource(
                        documentID: document.id,
                        documentTitle: document.title,
                        sectionID: section.id,
                        sectionTitle: section.title
                    )
                )
            }
        }
    }

    private static func score(_ passage: Passage, for terms: [String]) -> Int {
        let document = passage.source.documentTitle.lowercased()
        let heading = passage.source.sectionTitle.lowercased()
        let body = passage.text.lowercased()
        return terms.reduce(0) { total, term in
            total + (document.contains(term) ? 5 : 0) + (heading.contains(term) ? 4 : 0) + (body.contains(term) ? 1 : 0)
        }
    }

    private static func snippet(from markdown: String, matching terms: [String]) -> String {
        let lines = markdown.components(separatedBy: .newlines).map(clean).filter { $0.count >= 8 }
        let selected = lines.first { line in terms.contains { line.lowercased().contains($0) } } ?? lines.first ?? "No readable excerpt."
        return selected.count > 220 ? String(selected.prefix(217)) + "…" : selected
    }

    private static func firstUsefulLine(in markdown: String) -> String? {
        markdown.components(separatedBy: .newlines).map(clean).first { $0.count >= 8 }
    }

    private static func clean(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "> ", "### ", "#### "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }

    private static func tokens(in value: String) -> [String] {
        let stopWords: Set<String> = ["about", "and", "are", "can", "for", "from", "have", "here", "how", "into", "that", "the", "this", "what", "when", "where", "which", "with", "would", "you"]
        let terms: [String] = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Array(terms.prefix(12))
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    private static func uniqueSources(_ sources: [AtlasLocalSource]) -> [AtlasLocalSource] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.id).inserted }.prefix(12).map { $0 }
    }
}
