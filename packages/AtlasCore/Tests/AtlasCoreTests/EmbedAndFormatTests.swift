import Foundation
import Testing
@testable import AtlasCore

@Suite("Embedded notes")
struct EmbedTests {

    @Test("An embed is left alone, so it cannot be mistaken for an image")
    func embedsSurviveLinkResolution() {
        let source = "Here it is:\n![[CS 2100 · Exception handling]]\nand more text."
        let resolved = AtlasNoteLinks.resolvingWikiLinks(in: source)

        #expect(resolved.contains("![[CS 2100 · Exception handling]]"))
        #expect(!resolved.contains("![CS 2100"))
    }

    @Test("A link beside an embed still becomes a link")
    func linksAndEmbedsCoexist() {
        let source = "See [[Alpha]] and unfold:\n![[Beta]]"
        let resolved = AtlasNoteLinks.resolvingWikiLinks(in: source)

        #expect(resolved.contains("[Alpha](atlas-note:"))
        #expect(resolved.contains("![[Beta]]"))
    }

    @Test("Embedded and referenced titles are told apart")
    func embeddedTitlesAreDistinct() {
        let source = "[[Alpha]]\n![[Beta]]\n[[Gamma]]"
        #expect(AtlasNoteLinks.embeddedTitles(in: source) == ["Beta"])
        #expect(AtlasNoteLinks.referencedTitles(in: source) == ["Alpha", "Beta", "Gamma"])
    }

    @Test("An embed only counts when it is alone on its line")
    func embedsMustOwnTheirLine() {
        #expect(AtlasNoteLinks.embedTitle(inLine: "  ![[Alpha]]  ") == "Alpha")
        #expect(AtlasNoteLinks.embedTitle(inLine: "As in ![[Alpha]] above.") == nil)
        #expect(AtlasNoteLinks.embedTitle(inLine: "[[Alpha]]") == nil)
        #expect(AtlasNoteLinks.embedTitle(inLine: "![[]]") == nil)
    }
}

@Suite("Note blocks")
struct MarkdownBlockTests {

    @Test("A sub-point stays a sub-point")
    func listsKeepTheirNesting() throws {
        let source = """
        - Handling errors
          - SyntaxError means the grammar is wrong
          - ValueError means the value is wrong
        - Tracing bugs with a debugger
        """
        let blocks = MarkdownBlockParser.parse(source)
        guard case let .list(list) = try #require(blocks.first) else {
            Issue.record("expected a list"); return
        }

        #expect(list.items.count == 2)
        let sublist = try #require(list.items[0].sublist)
        #expect(sublist.items.count == 2)
        #expect(sublist.items[0].text == "SyntaxError means the grammar is wrong")
        #expect(list.items[1].sublist == nil)
    }

    @Test("Three levels nest, rather than collapsing into two")
    func deepNestingSurvives() throws {
        let source = """
        - One
            - Two
                - Three
        """
        let blocks = MarkdownBlockParser.parse(source)
        guard case let .list(list) = try #require(blocks.first) else {
            Issue.record("expected a list"); return
        }
        let second = try #require(list.items[0].sublist)
        let third = try #require(second.items[0].sublist)
        #expect(third.items[0].text == "Three")
    }

    @Test("A bullet pasted from a slide deck is still a bullet")
    func unicodeBulletsAreRead() throws {
        let blocks = MarkdownBlockParser.parse("\u{2022} Writing tests with pytest")
        guard case let .list(list) = try #require(blocks.first) else {
            Issue.record("expected a list"); return
        }
        #expect(list.items[0].text == "Writing tests with pytest")
    }

    @Test("An embed line becomes its own block rather than a paragraph")
    func embedsBecomeBlocks() throws {
        let blocks = MarkdownBlockParser.parse("Before.\n\n![[Deep dive]]\n\nAfter.")
        #expect(blocks.count == 3)
        guard case let .embed(title) = blocks[1] else {
            Issue.record("expected an embed"); return
        }
        #expect(title == "Deep dive")
    }

    @Test("A hash inside fenced code stays code")
    func fencesAreRespected() throws {
        let source = """
        ```python
        # not a heading
        x = 1
        ```
        """
        let blocks = MarkdownBlockParser.parse(source)
        guard case let .code(language, content) = try #require(blocks.first) else {
            Issue.record("expected code"); return
        }
        #expect(language == "python")
        #expect(content.contains("# not a heading"))
    }

    @Test("Checklists keep their state")
    func checklistsParse() throws {
        let blocks = MarkdownBlockParser.parse("- [ ] Read chapter 2\n- [x] Install pytest")
        guard case let .list(list) = try #require(blocks.first) else {
            Issue.record("expected a list"); return
        }
        #expect(list.items[0].checked == false)
        #expect(list.items[1].checked == true)
    }
}

@Suite("Note format")
struct NoteFormatTests {

    private func context() -> LectureNoteContext {
        LectureNoteContext(
            lectureID: "lecture-1",
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 3_000,
            courseTitle: "CS 2100",
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            segments: [],
            transcriptText: "Exceptions interrupt execution."
        )
    }

    private func structure() -> LectureStructure {
        LectureStructure(
            title: "Code quality",
            summary: "Errors, exceptions and the debugger.",
            keyPoints: ["Read a traceback from the bottom up"],
            outline: [
                LectureOutlineItem(heading: "Errors", points: ["Syntax errors and exceptions"]),
                LectureOutlineItem(heading: "Debugging", points: ["Step over, step into, step out"])
            ],
            reviewQuestions: ["What does `raise` do?"],
            deepDives: [
                LectureDeepDive(
                    title: "Exception handling",
                    section: "errors",
                    summary: "try, except, finally in full.",
                    markdown: String(repeating: "A full walk through try and except. ", count: 10)
                )
            ]
        ).normalized()
    }

    @Test("A companion opens inside the section it belongs to")
    func companionIsEmbeddedInItsSection() {
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "Code quality — source & depth"
        )
        let body = note.markdown
        let errorsHeading = body.range(of: "### Errors")!
        let embed = body.range(of: "![[CS 2100 · Exception handling]]")!
        let debuggingHeading = body.range(of: "### Debugging")!

        // Between the heading it explains and the next one, not in an index.
        #expect(errorsHeading.upperBound < embed.lowerBound)
        #expect(embed.upperBound < debuggingHeading.lowerBound)
        #expect(!body.contains("## Going deeper"))
    }

    @Test("A companion whose section does not exist is still reachable")
    func unmatchedCompanionIsGatheredAtTheEnd() {
        var value = structure()
        value.deepDives = [
            LectureDeepDive(
                title: "Context managers",
                section: "A section that is not in the outline",
                summary: "with statements.",
                markdown: String(repeating: "Setup and cleanup around a block. ", count: 10)
            )
        ]
        let note = LectureNoteBuilder.studyNote(
            structure: value.normalized(),
            context: context(),
            depthTitle: "Code quality — source & depth"
        )
        #expect(note.markdown.contains("## Going deeper"))
        #expect(note.markdown.contains("![[CS 2100 · Context managers]]"))
    }

    @Test("Turning embedding off leaves a link instead")
    func embeddingCanBeTurnedOff() {
        var format = NoteFormatPreferences.standard
        format.embedsCompanions = false
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "Code quality — source & depth",
            format: format
        )
        #expect(!note.markdown.contains("![[CS 2100 · Exception handling]]"))
        #expect(note.markdown.contains("[[CS 2100 · Exception handling]]"))
    }

    @Test("A section turned off does not appear")
    func sectionsCanBeTurnedOff() {
        let format = NoteFormatPreferences.standard
            .setting(.reviewQuestions, to: false)
            .setting(.keyPoints, to: false)
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "Code quality — source & depth",
            format: format
        )
        #expect(!note.markdown.contains("## Questions to review"))
        #expect(!note.markdown.contains("## Key points"))
        #expect(note.markdown.contains("## Outline"))
    }

    @Test("Detail changes what the model is asked for, not just what is shown")
    func detailReachesThePrompt() {
        var tight = NoteFormatPreferences.standard
        tight.detail = .tight
        let prompt = LecturePrompts.extractionSystem(format: tight)
        #expect(prompt.contains("Keep this tight."))
    }

    @Test("A companion's own headings are pushed down so the note keeps a shape")
    func companionHeadingsAreDemoted() {
        let dive = LectureDeepDive(
            title: "Exception handling",
            summary: "try and except.",
            markdown: "## Raising\n\nUse `raise`.\n\n```python\n# heading-looking comment\n```"
        )
        let note = LectureNoteBuilder.deepDiveNote(dive, context: context(), parentTitle: "Code quality")

        #expect(note.markdown.contains("### Raising"))
        // Only three sections of its own: what it is, the idea, where it came from.
        #expect(MarkdownSections.parse(note.markdown).count == 3)
        // A comment inside a fence is not a heading and must not be demoted.
        #expect(note.markdown.contains("# heading-looking comment"))
    }

    @Test("What Atlas was told is recorded in the file the assistant reads")
    func briefingIsRecordedInTheSourceNote() {
        var informed = context()
        informed = LectureNoteContext(
            lectureID: informed.lectureID,
            recordedAt: informed.recordedAt,
            durationSeconds: informed.durationSeconds,
            courseTitle: informed.courseTitle,
            transcriptionEngine: informed.transcriptionEngine,
            modelIdentifier: informed.modelIdentifier,
            segments: informed.segments,
            transcriptText: informed.transcriptText,
            briefingNote: "Everything is Python 3."
        )
        let note = LectureNoteBuilder.depthNote(
            structure: structure(),
            context: informed,
            studyTitle: "Code quality"
        )
        #expect(note.markdown.contains("## What Atlas was told about this course"))
        #expect(note.markdown.contains("Everything is Python 3."))
    }
}
