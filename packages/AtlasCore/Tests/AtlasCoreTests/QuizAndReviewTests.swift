import Foundation
import Testing
@testable import AtlasCore

@Suite("Quiz and activities")
struct QuizTests {

    private func context() -> LectureNoteContext {
        LectureNoteContext(
            lectureID: "lecture-1",
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 5_400,
            courseTitle: "MKTG2201",
            transcriptionEngine: "Apple Speech (on device)",
            modelIdentifier: "Ollama · gpt-oss:20b",
            segments: [],
            transcriptText: "Marketing is engaging customers and managing profitable relationships."
        )
    }

    private func structure() -> LectureStructure {
        LectureStructure(
            title: "What is marketing?",
            summary: "The marketing process and the five core marketplace concepts.",
            keyPoints: ["A demand is a want backed by purchasing power"],
            activities: [
                LectureActivity(
                    title: "Group work: why Blackberry failed",
                    task: "In groups, work out why Blackberry lost the market.",
                    conclusion: "They kept optimising the keyboard while the market moved to apps.",
                    whenLabel: "about an hour in"
                )
            ],
            quiz: [
                LectureQuizQuestion(
                    question: "What separates a want from a demand?",
                    answer: "Purchasing power",
                    explanation: "A want becomes a demand once the buyer can actually pay for it.",
                    source: "both"
                ),
                LectureQuizQuestion(
                    question: "Which is NOT one of the five core marketplace concepts?",
                    options: ["Needs and wants", "Market offerings", "Quarterly earnings"],
                    answer: "Quarterly earnings",
                    explanation: "The five are needs, offerings, value and satisfaction, exchange, and markets.",
                    source: "slides"
                )
            ]
        ).normalized()
    }

    @Test("A quiz answer is written as a callout, so it can be hidden")
    func quizAnswersAreCallouts() {
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "What is marketing? — source & depth"
        )
        #expect(note.markdown.contains("## Test yourself"))
        #expect(note.markdown.contains("**1.** What separates a want from a demand?"))
        #expect(note.markdown.contains("> [!answer] Purchasing power"))
        // Multiple choice renders its options as an ordinary list.
        #expect(note.markdown.contains("- Quarterly earnings"))
    }

    @Test("An activity is summarised, never transcribed")
    func activitiesAreSummarised() {
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "x"
        )
        #expect(note.markdown.contains("## In class"))
        #expect(note.markdown.contains("Group work: why Blackberry failed"))
        #expect(note.markdown.contains("**The task.**"))
        #expect(note.markdown.contains("**What came of it.**"))
    }

    @Test("Both sections can be turned off")
    func sectionsCanBeTurnedOff() {
        let format = NoteFormatPreferences.standard
            .setting(.quiz, to: false)
            .setting(.activities, to: false)
        let note = LectureNoteBuilder.studyNote(
            structure: structure(),
            context: context(),
            depthTitle: "x",
            format: format
        )
        #expect(!note.markdown.contains("## Test yourself"))
        #expect(!note.markdown.contains("## In class"))
    }

    @Test("A question with no answer is dropped rather than left unanswerable")
    func answerlessQuestionsAreDropped() {
        let cleaned = LectureStructure(
            quiz: [
                LectureQuizQuestion(question: "What is marketing?", answer: ""),
                LectureQuizQuestion(question: "What is a demand?", answer: "A want with money behind it")
            ]
        ).normalized()
        #expect(cleaned.quiz.count == 1)
        #expect(cleaned.quiz[0].question == "What is a demand?")
    }

    @Test("A quiz is capped at ten questions")
    func quizIsBounded() {
        let many = (1...25).map {
            LectureQuizQuestion(question: "Question \($0)?", answer: "Answer \($0)")
        }
        #expect(LectureStructure(quiz: many).normalized().quiz.count == 10)
    }
}

@Suite("Callout blocks")
struct CalloutTests {

    @Test("An answer callout is its own block, not a quote")
    func calloutsParse() throws {
        let blocks = MarkdownBlockParser.parse("**1.** What is a demand?\n\n> [!answer] A want backed by purchasing power.")
        guard case let .callout(kind, text) = try #require(blocks.last) else {
            Issue.record("expected a callout"); return
        }
        #expect(kind == "answer")
        #expect(text == "A want backed by purchasing power.")
    }

    @Test("An ordinary quote is still a quote")
    func quotesAreUnaffected() throws {
        let blocks = MarkdownBlockParser.parse("> Marketing is a social and managerial process.")
        guard case .quote = try #require(blocks.first) else {
            Issue.record("expected a quote"); return
        }
    }

    @Test("A callout continues over the lines beneath it")
    func calloutsSpanLines() throws {
        let blocks = MarkdownBlockParser.parse("> [!answer] Purchasing power.\n> It is what turns a want into a demand.")
        guard case let .callout(_, text) = try #require(blocks.first) else {
            Issue.record("expected a callout"); return
        }
        #expect(text == "Purchasing power. It is what turns a want into a demand.")
    }

    @Test("Two callouts in a row stay separate")
    func consecutiveCalloutsDoNotMerge() {
        let blocks = MarkdownBlockParser.parse("> [!answer] First.\n> [!answer] Second.")
        #expect(blocks.count == 2)
    }

    @Test("A bracket that is not a callout is left as a quote")
    func malformedCalloutsAreQuotes() throws {
        let blocks = MarkdownBlockParser.parse("> [not a callout] text")
        guard case .quote = try #require(blocks.first) else {
            Issue.record("expected a quote"); return
        }
    }
}

@Suite("Slide outline")
struct SlideOutlineTests {

    @Test("The deck's terms are put in front of the transcript pass")
    func outlineReachesThePrompt() throws {
        let outline = LectureSlideOutline(
            title: "What is marketing?",
            objectives: ["Define marketing and outline the steps in the marketing process"],
            sections: [.init(heading: "Needs, wants and demands", startsAt: "slide 7")],
            terms: [
                .init(term: "societal marketing concept", definition: "Meeting today's needs without compromising future generations."),
                .init(term: "customer engagement")
            ]
        ).normalized()

        let block = try #require(outline.promptBlock)
        #expect(block.contains("societal marketing concept"))
        #expect(block.contains("customer engagement"))
        #expect(block.contains("slide 7"))
        // The instruction that makes the terms useful, not just present.
        #expect(block.contains("it IS this"))

        let prompt = LecturePrompts.extractionSystem(outline: outline)
        #expect(prompt.contains("societal marketing concept"))
    }

    @Test("An empty deck contributes nothing rather than an empty heading")
    func emptyOutlineIsSilent() {
        #expect(LectureSlideOutline().promptBlock == nil)
        #expect(!LecturePrompts.extractionSystem().contains("THE SLIDES FOR THIS LECTURE"))
    }

    @Test("Every pass opens with the house style")
    func houseStyleLeadsEveryPass() {
        for prompt in [
            LecturePrompts.extractionSystem(),
            LecturePrompts.consolidationSystem(),
            LecturePrompts.reviewSystem(),
            LecturePrompts.quizSystem(),
            LecturePrompts.outlineSystem(),
            LecturePrompts.attachmentSystem()
        ] {
            #expect(prompt.hasPrefix("You are writing study notes for one university student"))
            #expect(prompt.contains("THE SHAPE OF A FINISHED NOTE"))
        }
    }

    @Test("The house style is a preamble, never a pass of its own")
    func houseStyleIsNotAStage() {
        #expect(LectureSkill.houseStyle.isPreamble)
        #expect(!LectureSkill.review.isPreamble)
        // Editing it changes every pass at once.
        let edited = LectureSkillSet.standard.setting("House rule: be terse.", for: .houseStyle)
        #expect(LecturePrompts.quizSystem(skills: edited).hasPrefix("House rule: be terse."))
        #expect(LecturePrompts.extractionSystem(skills: edited).hasPrefix("House rule: be terse."))
    }
}

@Suite("Review corrections")
struct ReviewTests {

    @Test("Corrections are bounded and de-duplicated")
    func reviewIsNormalised() {
        let review = LectureReview(corrections: (1...40).map {
            LectureCorrection(problem: "Problem \($0 % 3)", kind: "noise")
        }).normalized()
        #expect(review.corrections.count == 3)
    }

    @Test("A correction with no problem named is dropped")
    func emptyProblemsAreDropped() {
        let review = LectureReview(corrections: [
            LectureCorrection(problem: "  ", kind: "noise"),
            LectureCorrection(problem: "IKEA bullet came from students chatting", kind: "noise")
        ]).normalized()
        #expect(review.corrections.count == 1)
    }

    @Test("The review instructions put noise first, because that is what leaks")
    func reviewLeadsWithNoise() {
        let prompt = LecturePrompts.reviewSystem()
        let noise = prompt.range(of: "NOISE THAT LEAKED IN")!
        let unsupported = prompt.range(of: "CLAIMS THE TRANSCRIPT DOES NOT SUPPORT")!
        #expect(noise.lowerBound < unsupported.lowerBound)
    }
}

@Suite("Sampling a long transcript")
struct TranscriptSamplerTests {

    /// A group activity is minutes long, not a single phrase — several
    /// thousand characters of crosstalk. That is what has to be caught.
    private func transcript(activity: String, at fraction: Double, length: Int = 4_000) -> String {
        let total = 60_000
        let filler = String(repeating: "the lecturer continued speaking. ", count: total / 33)
        var characters = Array(filler.prefix(total))
        let stretch = Array(String(repeating: activity + " ", count: length / (activity.count + 1)))
        let position = Int(Double(total) * fraction)
        characters.replaceSubrange(position..<min(total, position + stretch.count), with: stretch.prefix(min(stretch.count, total - position)))
        return String(characters)
    }

    @Test("A stretch of noise three quarters in is seen, which a prefix would miss")
    func samplingReachesTheMiddleAndEnd() {
        let text = transcript(activity: "BLACKBERRY_ACTIVITY", at: 0.75)
        let budget = 18_000

        #expect(!String(text.prefix(budget)).contains("BLACKBERRY_ACTIVITY"))
        #expect(TranscriptSampler.evenlySampled(text, budget: budget).contains("BLACKBERRY_ACTIVITY"))
    }

    @Test("The gap between windows is small enough that an activity cannot hide in it")
    func gapIsBoundedBelowAnActivity() {
        // A 90-minute lecture, the budget a 20B model gets, and roughly the
        // length of a few minutes of speech.
        let gap = TranscriptSampler.largestGap(totalCharacters: 60_000, budget: 18_000)
        #expect(gap < 3_000)

        // And the guarantee holds: a stretch longer than the gap is always hit.
        for fraction in stride(from: 0.05, through: 0.95, by: 0.05) {
            let text = transcript(activity: "NOISE", at: fraction, length: gap + 500)
            #expect(
                TranscriptSampler.evenlySampled(text, budget: 18_000).contains("NOISE"),
                "a stretch longer than the gap was missed at \(fraction)"
            )
        }
    }

    @Test("The closing minutes are reached, where the homework is")
    func samplingReachesTheEnd() {
        let text = transcript(activity: "READ_CHAPTER_TWO", at: 0.985, length: 600)
        #expect(TranscriptSampler.evenlySampled(text, budget: 18_000).contains("READ_CHAPTER_TWO"))
    }

    @Test("The sample stays inside its budget")
    func samplingRespectsTheBudget() {
        let text = transcript(activity: "x", at: 0.5)
        let sample = TranscriptSampler.evenlySampled(text, budget: 12_000)
        // The elision markers add a little; the transcript itself must not.
        let withoutMarkers = sample.replacingOccurrences(
            of: "\n\n[…a stretch of the recording is not shown here…]\n\n",
            with: ""
        )
        #expect(withoutMarkers.count <= 12_000)
    }

    @Test("A transcript that already fits is returned whole")
    func shortTranscriptsAreUntouched() {
        let short = "An index is a lookup structure."
        #expect(TranscriptSampler.evenlySampled(short, budget: 4_000) == short)
    }

    @Test("Gaps are marked, so two windows are not read as one sentence")
    func gapsAreVisible() {
        let sample = TranscriptSampler.evenlySampled(transcript(activity: "x", at: 0.5), budget: 8_000)
        #expect(sample.contains("a stretch of the recording is not shown here"))
    }
}
