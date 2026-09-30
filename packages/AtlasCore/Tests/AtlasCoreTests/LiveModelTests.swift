import Foundation
import Testing
@testable import AtlasCore

/*
 Checks that run against the local model actually installed on this machine.

 Skipped unless ATLAS_LIVE_MODEL is set: they need Ollama running and take
 minutes. They exist because what is being fixed here — a model reading a
 transcript without knowing what the course is — cannot be caught by a test that
 asserts on a canned reply. Only a real model can get it wrong.

 The transcript below is written so that context is the ONLY thing that can
 produce the right answer. Every technical term the course actually uses arrives
 mis-heard, the way automatic transcription delivers them, and nothing in the
 surrounding words gives them away.
*/
@Suite("Live model", .enabled(if: ProcessInfo.processInfo.environment["ATLAS_LIVE_MODEL"] != nil))
struct LiveModelTests {

    /// Mis-hearings a recogniser really produces: "pie test" for pytest,
    /// "assert" heard as "a search", "PDB" as "PDP".
    static let garbledTranscript = """
    Right, so this week is about checking that your code does what you think it does.
    We'll write our tests using pie test, which is the framework for this module, and
    inside each test you use a search statements rather than any special comparison
    methods. A search takes an expression, and if the expression is false the test fails
    and you get told which line it was.
    So you write a function whose name starts with test, underscore, and inside it you
    call the thing you're testing and then a search that the answer is what you expect.
    You run the whole suite from the terminal and it tells you how many passed.
    If a test fails and you can't see why, you drop into the debugger. PDP dot set trace
    is the old way, or you just use breakpoint, and then you step through it.
    Someone asked about mocking last week. We're not covering that this term.
    """

    static let transcript = garbledTranscript

    private func client() async throws -> OllamaModelClient {
        guard let client = await OllamaModelClient.discover() else {
            Issue.record("Ollama is not running")
            throw LectureModelError.notReachable("Ollama")
        }
        return client
    }

    private func notesText(_ structure: LectureStructure) -> String {
        ([structure.title, structure.summary]
            + structure.keyPoints
            + structure.topics
            + structure.outline.flatMap { [$0.heading] + $0.points }
            + structure.glossary.flatMap { [$0.term, $0.shortDefinition] })
            .joined(separator: " ")
            .lowercased()
    }

    @Test("Course context repairs terms the transcript mis-heard", .timeLimit(.minutes(5)))
    func contextRepairsMisheardTerms() async throws {
        let service = LectureStructuringService(client: try await client())
        let briefing = LectureBriefing(
            coursePath: "School › CS 2100",
            courseBriefing: """
            This course is taught entirely in Python 3. We never use Java or C.
            Tests are written with pytest, using plain assert statements.
            The debugger is pdb.
            """
        )

        let informed = try await service.makeStructure(
            segments: [],
            transcriptText: Self.garbledTranscript,
            hint: "CS 2100",
            durationSeconds: 1_800,
            briefing: briefing
        )
        let text = notesText(informed)
        print("LIVE informed title: \(informed.title)")
        print("LIVE informed terms: \(informed.glossary.map(\.term).joined(separator: ", "))")

        // The written name, not the sound of it.
        #expect(text.contains("pytest"))
        #expect(text.contains("assert"))
        #expect(!text.contains("pie test"))
    }

    @Test("The model picks the right folder, and nests a new class with the others", .timeLimit(.minutes(5)))
    func placementUsesTheTree() async throws {
        let service = LectureStructuringService(client: try await client())
        let options = [
            LecturePlacementOption(id: "school", path: "School", summary: "Everything for university", noteCount: 0, childCount: 2),
            LecturePlacementOption(id: "mktg", path: "School › Marketing", summary: "MKTG2201 Introduction to Marketing", noteCount: 2, childCount: 0),
            LecturePlacementOption(id: "ds", path: "School › DS 1800", summary: "Data science", noteCount: 4, childCount: 0)
        ]

        let decision = try #require(
            await service.decidePlacement(
                structure: LectureStructure(
                    title: "Code quality: errors, exceptions and the debugger",
                    courseName: "Program Design and Implementation",
                    courseCode: "CS2100",
                    summary: "Handling errors, context managers, the debugger, and writing tests with pytest.",
                    topics: ["errors", "exceptions", "debugging", "pytest"]
                ),
                hint: "CS 2100",
                options: options
            )
        )
        print("LIVE placement: \(decision.proposedCollectionTitle) parent=\(decision.proposedParentID ?? "none")")

        #expect(decision.createsCollection)
        #expect(decision.proposedParentID == "school")
    }

    @Test("An existing class is recognised rather than duplicated", .timeLimit(.minutes(5)))
    func placementFindsAnExistingCourse() async throws {
        let service = LectureStructuringService(client: try await client())
        let options = [
            LecturePlacementOption(id: "school", path: "School", summary: "Everything for university", noteCount: 0, childCount: 2),
            LecturePlacementOption(id: "mktg", path: "School › Marketing", summary: "MKTG2201 Introduction to Marketing", noteCount: 2, childCount: 0),
            LecturePlacementOption(id: "cs", path: "School › CS 2100", summary: "Program Design and Implementation 1", noteCount: 3, childCount: 0)
        ]

        let decision = try #require(
            await service.decidePlacement(
                structure: LectureStructure(
                    title: "Writing tests with pytest",
                    courseCode: "CS2100",
                    summary: "Test functions, assert statements, running the suite."
                ),
                hint: "CS 2100",
                options: options
            )
        )
        print("LIVE existing: \(decision.proposedCollectionTitle) id=\(decision.existingCollectionID ?? "new")")
        #expect(decision.existingCollectionID == "cs")
    }
}

/// The control arm: the same garbled transcript with nothing told. Separated so
/// the suite above stays a set of assertions about Atlas, and this stays what it
/// is — a comparison, printed rather than asserted, because a test that requires
/// a model to get something wrong fails the day the model improves.
@Suite("Live control", .enabled(if: ProcessInfo.processInfo.environment["ATLAS_LIVE_CONTROL"] != nil))
struct LiveControlTests {
    @Test("Without context", .timeLimit(.minutes(5)))
    func withoutContext() async throws {
        guard let client = await OllamaModelClient.discover() else { return }
        let service = LectureStructuringService(client: client)
        let result = try await service.makeStructure(
            segments: [],
            transcriptText: LiveModelTests.garbledTranscript,
            hint: "CS 2100",
            durationSeconds: 1_800
        )
        let text = ([result.title, result.summary] + result.topics + result.keyPoints
            + result.outline.flatMap { [$0.heading] + $0.points }
            + result.glossary.flatMap { [$0.term, $0.shortDefinition] })
            .joined(separator: " ").lowercased()

        print("CONTROL title: \(result.title)")
        print("CONTROL terms: \(result.glossary.map(\.term).joined(separator: ", "))")
        print("CONTROL says pytest: \(text.contains("pytest"))")
        print("CONTROL says 'pie test': \(text.contains("pie test"))")
        print("CONTROL says assert: \(text.contains("assert"))")
    }
}
