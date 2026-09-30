import Foundation
import Testing
@testable import AtlasCore

@Suite("Atlas core")
struct AtlasCoreTests {
    @Test("Markdown sections preserve content and unique navigation IDs")
    func markdownSections() {
        let sections = MarkdownSections.parse(
            """
            Opening context.

            ## Next steps

            First action.

            ## Next steps

            Second action.
            """
        )

        #expect(sections.map(\.title) == ["Overview", "Next steps", "Next steps"])
        #expect(sections.map(\.id) == ["overview", "next-steps", "next-steps-2"])
        #expect(sections[2].markdown.contains("Second action"))
    }

    @Test("Unknown seed fields do not break decoding")
    func seedDecodingIsAdditive() throws {
        let data = Data(
            """
            [{
              "id":"inbox","title":"Inbox","description":"Notes","icon":"folder",
              "accent":"gold","order":1,"future_field":"safe",
              "documents":[]
            }]
            """.utf8
        )
        let collections = try JSONDecoder().decode([SeedCollection].self, from: data)
        #expect(collections.first?.id == "inbox")
    }

    @Test("A document without headings remains readable")
    func headinglessDocument() {
        let sections = MarkdownSections.parse("A short standalone note.")
        #expect(sections.count == 1)
        #expect(sections[0].title == "Overview")
    }

    @Test("Headings inside code fences stay inside their section")
    func fencedHeading() {
        let sections = MarkdownSections.parse(
            """
            ## Authoring example

            ```markdown
            ## This is example text, not navigation
            ```

            ## Real section

            Content.
            """
        )
        #expect(sections.map(\.title) == ["Authoring example", "Real section"])
        #expect(sections[0].markdown.contains("## This is example text, not navigation"))
    }

    @Test("Agent requests round-trip with a stable version")
    func agentRequestRoundTrip() throws {
        let request = AtlasAgentRequest(
            operation: .searchNotes,
            arguments: AtlasAgentArguments(query: "internships", limit: 10)
        )
        let encoder = AtlasAgentJSON.encoder()
        let data = try encoder.encode(request)
        let decoder = AtlasAgentJSON.decoder()
        let decoded = try decoder.decode(AtlasAgentRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.version == 1)
    }

    @Test("Agent JSON preserves sub-second update versions")
    func agentDatePrecision() throws {
        let date = Date(timeIntervalSince1970: 1_788_676_543.987_654)
        let note = AtlasDocumentSnapshot(
            id: "note-id",
            collectionID: "collection-id",
            title: "Note",
            summary: "",
            category: "Notes",
            updatedAt: date,
            accent: "slate",
            bodyMarkdown: "## Note",
            isFavorite: false
        )
        let encoded = try AtlasAgentJSON.encoder().encode(note)
        let decoded = try AtlasAgentJSON.decoder().decode(AtlasDocumentSnapshot.self, from: encoded)
        #expect(abs(decoded.updatedAt.timeIntervalSince(date)) < 0.001)
    }

    @Test("Agent updates require the exact version last read")
    @MainActor
    func agentUpdateConflictProtection() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collectionID = try store.createCollection(title: "Test")
        let noteID = try store.createDocument(in: collectionID, title: "Draft")
        let initial = try #require(store.document(id: noteID))

        let update = AtlasAgentRequest(
            operation: .updateNote,
            arguments: AtlasAgentArguments(
                noteID: noteID,
                title: "Updated",
                expectedUpdatedAt: initial.updatedAt.addingTimeInterval(-1)
            )
        )

        #expect(throws: AtlasAgentProtocolError.self) {
            try store.handleAgentRequest(update)
        }
        #expect(store.document(id: noteID)?.title == "Draft")
    }

    @Test("Agent can create and search notes through the public protocol")
    @MainActor
    func agentCreateAndSearch() throws {
        let store = try AtlasLibraryStore(inMemory: true)
        let collectionID = try store.createCollection(title: "Career")
        let create = AtlasAgentRequest(
            operation: .createNote,
            arguments: AtlasAgentArguments(
                collectionID: collectionID,
                title: "Interview prep",
                markdown: "## Practice\n\nLeetCode arrays"
            )
        )
        let created = try store.handleAgentRequest(create)
        #expect(created.ok)

        let search = AtlasAgentRequest(
            operation: .searchNotes,
            arguments: AtlasAgentArguments(query: "LeetCode")
        )
        let matches = try store.handleAgentRequest(search)
        #expect(matches.payload?.notes?.first?.title == "Interview prep")
    }

    @Test("Local assistant answers only from the selected document")
    func localAssistantDocumentScope() {
        let selected = AtlasDocumentSnapshot(
            id: "selected",
            collectionID: "career",
            title: "Interview plan",
            summary: "Prepare for technical interviews.",
            category: "Plan",
            updatedAt: .now,
            accent: "forest",
            bodyMarkdown: "## Practice\n\n- [ ] Review array problems\n\n## Timing\n\nApply before October.",
            isFavorite: false
        )
        let unrelated = AtlasDocumentSnapshot(
            id: "other",
            collectionID: "career",
            title: "Private unrelated note",
            summary: "",
            category: "Note",
            updatedAt: .now,
            accent: "slate",
            bodyMarkdown: "## Secret topic\n\nThis should not enter document-scoped results.",
            isFavorite: false
        )
        let context = AtlasLocalContext(collection: nil, document: selected, documents: [selected, unrelated])

        let result = AtlasLocalAssistant.answer("What should I do next?", in: context)
        #expect(result.body.contains("Review array problems"))
        #expect(!result.body.contains("Secret topic"))
        #expect(result.sources.allSatisfy { $0.documentID == "selected" })
    }

    @Test("Local assistant searches across the selected collection and cites matches")
    func localAssistantCollectionSearch() {
        let first = AtlasDocumentSnapshot(
            id: "one", collectionID: "career", title: "Applications", summary: "", category: "Plan",
            updatedAt: .now, accent: "forest", bodyMarkdown: "## Deadlines\n\nThe application deadline is October 4.", isFavorite: false
        )
        let second = AtlasDocumentSnapshot(
            id: "two", collectionID: "career", title: "Interviews", summary: "", category: "Guide",
            updatedAt: .now, accent: "gold", bodyMarkdown: "## Practice\n\nUse timed mock interviews.", isFavorite: false
        )
        let context = AtlasLocalContext(collection: nil, document: nil, documents: [first, second])

        let result = AtlasLocalAssistant.answer("When is the application deadline?", in: context)
        #expect(result.body.contains("October 4"))
        #expect(result.sources.first?.documentID == "one")
    }

    @Test("Local assistant bounds question input and reports missing evidence")
    func localAssistantNoFabrication() {
        let note = AtlasDocumentSnapshot(
            id: "one", collectionID: "general", title: "Groceries", summary: "", category: "Note",
            updatedAt: .now, accent: "slate", bodyMarkdown: "## List\n\nMilk and bread.", isFavorite: false
        )
        let result = AtlasLocalAssistant.answer(
            String(repeating: "astronomy ", count: 100),
            in: AtlasLocalContext(collection: nil, document: note, documents: [note])
        )
        #expect(result.title == "I couldn't find that here")
        #expect(!result.body.contains("planet"))
    }
}
