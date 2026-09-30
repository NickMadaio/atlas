import Foundation
import Testing
@testable import AtlasCore

/*
 The whole pipeline, on a real 90-minute lecture.

 Gated behind ATLAS_REAL_LECTURE and a fixtures directory, because it needs
 Ollama and takes half an hour. It exists because the two things being fixed —
 slide-informed term repair, and throwing away twenty minutes of group work —
 cannot be demonstrated on anything smaller. The transcript is the one Atlas
 actually produced: "society of Martin concept", "Spotify rap", "customer
 invasion part", and several thousand words of students arguing about IKEA.
*/
@Suite(
    "Real lecture",
    .enabled(if: ProcessInfo.processInfo.environment["ATLAS_REAL_LECTURE"] != nil)
)
struct RealLectureTests {

    private var fixtures: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["ATLAS_FIXTURES"] ?? "")
    }

    private func text(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    /// Mis-hearings that are in the transcript and must not survive into notes.
    private static let garbled = [
        "society of martin", "spotify rap", "customer invasion",
        "two-way community", "value shape"
    ]

    /// What the deck actually calls them.
    private static let correct = [
        "societal marketing", "customer engagement", "value chain"
    ]

    @Test("Slides repair the transcript, and group work stays out", .timeLimit(.minutes(60)))
    func fullPipelineOnRealLecture() async throws {
        guard let client = await OllamaModelClient.discover() else {
            Issue.record("Ollama is not running"); return
        }
        let transcript = try text("marketing-transcript.txt")
        let slides = try text("marketing-slides.txt")
        let context = try text("marketing-context.txt")

        let service = LectureStructuringService(client: client)
        let briefing = LectureBriefing(
            coursePath: "School › Marketing",
            courseBriefing: "MKTG2201 Introduction to Marketing. The slides are authoritative.",
            lectureNote: context
        )

        let started = Date()
        let structure = try await service.makeStructure(
            segments: [],
            transcriptText: transcript,
            hint: "Marketing",
            durationSeconds: 5_378,
            attachments: [LectureAttachmentText(name: "S2-7.pptx", text: slides, pageNoun: "slide")],
            briefing: briefing,
            format: .standard,
            onProgress: { print("  [\(Int($0.fraction * 100))%] \($0.stageLabel)") }
        )
        print("=== finished in \(Int(Date().timeIntervalSince(started) / 60)) min ===")

        let body = ([structure.title, structure.summary]
            + structure.keyPoints
            + structure.topics
            + structure.outline.flatMap { [$0.heading] + $0.points }
            + structure.glossary.flatMap { [$0.term, $0.shortDefinition] })
            .joined(separator: " ")
            .lowercased()

        print("TITLE: \(structure.title)")
        print("TOPICS: \(structure.topics.joined(separator: ", "))")
        print("TERMS: \(structure.glossary.map(\.term).joined(separator: ", "))")
        print("ACTIVITIES: \(structure.activities.map(\.title).joined(separator: " | "))")
        print("QUIZ: \(structure.quiz.count) questions")
        for question in structure.quiz {
            print("  Q: \(question.question)  →  \(question.answer)")
        }

        // 1. The deck's spelling wins over what the microphone heard.
        for mangled in Self.garbled {
            #expect(!body.contains(mangled), "mis-heard term survived: \(mangled)")
        }
        #expect(Self.correct.contains { body.contains($0) }, "no corrected term appeared")

        // 2. The lecture is the subject, not the activity.
        #expect(body.contains("marketing"))
        #expect(structure.outline.count >= 3)

        // 3. A quiz exists and every question can be answered.
        #expect((5...10).contains(structure.quiz.count))
        #expect(structure.quiz.allSatisfy { !$0.answer.trimmed.isEmpty })
    }
}
