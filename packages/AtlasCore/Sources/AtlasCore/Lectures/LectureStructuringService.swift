import Foundation

/// Runs the transcript through a local model, one slice at a time.
///
/// A lecture is longer than any local context window, so each slice is
/// structured on its own and the results are merged. A slice the model fails
/// on is skipped rather than fatal: partial notes from the rest of the hour
/// are worth far more than an error.
/// One attached document's readable text, page by page.
public struct LectureAttachmentText: Sendable, Hashable {
    public let name: String
    public let text: String
    public let pages: [AttachmentTextExtractor.Page]
    /// "slide" for a deck, "page" for a reading.
    public let pageNoun: String

    public init(
        name: String,
        text: String,
        pages: [AttachmentTextExtractor.Page] = [],
        pageNoun: String = "page"
    ) {
        self.name = name
        self.text = text
        self.pages = pages
        self.pageNoun = pageNoun
    }

    /// Falls back to a single page for a file that has no page structure, so
    /// everything downstream can assume pages exist.
    public var effectivePages: [AttachmentTextExtractor.Page] {
        pages.isEmpty ? [AttachmentTextExtractor.Page(number: 1, text: text)] : pages
    }
}

/// A slice of attached material, tagged with the pages it came from so the
/// model can cite them.
public struct LectureAttachmentChunk: Sendable, Hashable {
    public let documentName: String
    public let pageNoun: String
    public let firstPage: Int
    public let lastPage: Int
    public let index: Int
    public let total: Int
    public let text: String

    public var pageLabel: String {
        firstPage == lastPage
            ? "\(pageNoun) \(firstPage)"
            : "\(pageNoun)s \(firstPage)–\(lastPage)"
    }
}

public struct LectureStructuringService: Sendable {
    public struct Progress: Sendable, Equatable {
        public let completed: Int
        public let total: Int
        public let stageLabel: String

        public var fraction: Double {
            total <= 0 ? 0 : min(1, Double(completed) / Double(total))
        }
    }

    private let client: any LectureModelClient

    public init(client: any LectureModelClient) {
        self.client = client
    }

    public var modelIdentifier: String { client.identifier }

    public func makeStructure(
        segments: [AtlasLectureSegment],
        transcriptText: String,
        hint: String?,
        durationSeconds: Double,
        attachments: [LectureAttachmentText] = [],
        briefing: LectureBriefing = .none,
        skills: LectureSkillSet = .standard,
        format: NoteFormatPreferences = .standard,
        onProgress: @Sendable (Progress) -> Void = { _ in }
    ) async throws -> LectureStructure {
        let chunks = makeChunks(
            segments: segments,
            transcriptText: transcriptText,
            durationSeconds: durationSeconds
        )
        let attachmentWork = attachmentChunks(for: attachments)
        guard !chunks.isEmpty || !attachmentWork.isEmpty else { throw LectureModelError.unusableOutput }

        // The deck is read FIRST and becomes the skeleton: its section order is
        // the outline, and its spelling is what repairs the transcript's
        // mis-hearings while the transcript is still being read. Reading both
        // independently and merging afterwards never teaches the transcript
        // pass the right word.
        var outline: LectureSlideOutline?
        if !attachments.isEmpty {
            onProgress(Progress(completed: 0, total: 1, stageLabel: "Reading the slides"))
            outline = await surveyAttachments(attachments, skills: skills)
        }

        // One extraction per transcript chunk and per attachment chunk, a
        // consolidation when there is more than one result, then review,
        // revision and the quiz.
        let extractionCount = chunks.count + attachmentWork.count
        let reviewSteps = chunks.isEmpty ? 0 : format.reviewPasses * 2
        let totalSteps = extractionCount
            + (extractionCount > 1 ? 1 : 0)
            + reviewSteps
            + (format.includesQuiz ? 1 : 0)
        var merged: LectureStructure?
        var failures = 0

        for chunk in chunks {
            onProgress(
                Progress(
                    completed: chunk.index,
                    total: totalSteps,
                    stageLabel: "Reading \(chunk.rangeLabel)"
                )
            )
            try Task.checkCancellation()

            do {
                let raw = try await client.complete(
                    system: LecturePrompts.extractionSystem(skills: skills, briefing: briefing, outline: outline, format: format),
                    user: LecturePrompts.extractionUser(
                        chunk: chunk,
                        totalChunks: chunks.count,
                        hint: hint
                    )
                )
                guard let structure = LectureStructureParser.parse(raw) else {
                    failures += 1
                    continue
                }
                merged = merged.map { $0.merging(structure) } ?? structure.normalized()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
            }
        }

        // The lecture leads; attached material fills the gaps it left. Merging
        // keeps the first non-empty value, so slides never overwrite something
        // the lecturer actually said.
        for chunk in attachmentWork {
            onProgress(
                Progress(
                    completed: chunks.count + chunk.index,
                    total: totalSteps,
                    stageLabel: "Reading \(chunk.documentName), \(chunk.pageLabel)"
                )
            )
            try Task.checkCancellation()

            do {
                let raw = try await client.complete(
                    system: LecturePrompts.attachmentSystem(skills: skills, briefing: briefing),
                    user: LecturePrompts.attachmentUser(chunk: chunk, hint: hint)
                )
                guard let structure = LectureStructureParser.parse(raw) else {
                    failures += 1
                    continue
                }
                merged = merged.map { $0.merging(structure) } ?? structure.normalized()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
            }
        }

        guard var current = merged, !current.isEmpty else { throw LectureModelError.unusableOutput }
        var completed = extractionCount

        if extractionCount > 1 {
            onProgress(
                Progress(
                    completed: completed,
                    total: totalSteps,
                    stageLabel: "Pulling the lecture together"
                )
            )
            try Task.checkCancellation()

            // Consolidation is an improvement, not a requirement. If it fails
            // or comes back thinner than the merge, keep the merge.
            let consolidated = try? await client.complete(
                system: LecturePrompts.consolidationSystem(skills: skills, briefing: briefing, outline: outline, format: format),
                user: LecturePrompts.consolidationUser(merged: current, hint: hint)
            )
            if let consolidated,
               let final = LectureStructureParser.parse(consolidated),
               isAtLeastAsRich(final, as: current) {
                current = final
            }
            completed += 1
        }

        // Reading the draft back is where noise gets caught. A recording does
        // not pause for group work, so an hour of marketing contains minutes of
        // students talking over each other — and the pass that wrote the notes
        // has no way to know it was reading chatter. A second look, against the
        // transcript, does.
        for pass in 0..<(chunks.isEmpty ? 0 : format.reviewPasses) {
            onProgress(
                Progress(
                    completed: completed,
                    total: totalSteps,
                    stageLabel: format.reviewPasses > 1 ? "Checking the notes (\(pass + 1) of \(format.reviewPasses))" : "Checking the notes"
                )
            )
            try Task.checkCancellation()

            guard let review = await review(
                structure: current,
                transcriptText: transcriptText,
                segments: segments,
                briefing: briefing,
                outline: outline,
                skills: skills
            ), !review.corrections.isEmpty else {
                completed += 2
                // A clean pass means a clean draft; running a second one that
                // has nothing to work on only invites invention.
                break
            }
            completed += 1

            onProgress(Progress(completed: completed, total: totalSteps, stageLabel: "Applying \(review.corrections.count) correction\(review.corrections.count == 1 ? "" : "s")"))
            try Task.checkCancellation()

            if let revised = await revise(
                structure: current,
                review: review,
                briefing: briefing,
                skills: skills,
                format: format
            ) {
                current = revised
            }
            completed += 1
        }

        if format.includesQuiz {
            onProgress(Progress(completed: completed, total: totalSteps, stageLabel: "Writing a quiz"))
            try Task.checkCancellation()
            if let quiz = await makeQuiz(structure: current, skills: skills), !quiz.isEmpty {
                current.quiz = quiz
            }
        }

        onProgress(Progress(completed: totalSteps, total: totalSteps, stageLabel: "Finishing"))
        return current.normalized()
    }

    /// Reads the deck before anything else, for the lecture's shape and the
    /// correct spelling of its terms. Nil when it cannot be read: the pipeline
    /// then behaves exactly as it did before, rather than failing.
    public func surveyAttachments(
        _ attachments: [LectureAttachmentText],
        skills: LectureSkillSet = .standard
    ) async -> LectureSlideOutline? {
        let text = attachments
            .map { "--- \($0.name) ---\n\($0.text)" }
            .joined(separator: "\n\n")
        guard text.trimmed.count >= 80 else { return nil }
        // The survey wants breadth, not depth: the first slides carry the
        // objectives and the section list, which is most of the value.
        let budget = max(2_000, client.chunkCharacterBudget * 2)

        guard let raw = try? await client.complete(
            system: LecturePrompts.outlineSystem(skills: skills),
            user: LecturePrompts.outlineUser(
                text: String(text.prefix(budget)),
                documentNames: attachments.map(\.name)
            )
        ) else { return nil }

        guard let outline = LectureStructureParser.parse(raw, as: LectureSlideOutline.self) else { return nil }
        let clean = outline.normalized()
        return clean.isEmpty ? nil : clean
    }

    /// Reads the draft back against the transcript and reports what is wrong.
    public func review(
        structure: LectureStructure,
        transcriptText: String,
        segments: [AtlasLectureSegment],
        briefing: LectureBriefing = .none,
        outline: LectureSlideOutline? = nil,
        skills: LectureSkillSet = .standard
    ) async -> LectureReview? {
        let source = segments.isEmpty ? transcriptText : segments.map(\.text).joined(separator: " ")
        guard !source.trimmed.isEmpty else { return nil }

        guard let raw = try? await client.complete(
            system: LecturePrompts.reviewSystem(skills: skills, briefing: briefing, outline: outline),
            user: LecturePrompts.reviewUser(
                structure: structure,
                // Spread across the whole recording, not the first slice of
                // it: what the review is looking for is usually in the middle.
                transcriptExcerpt: TranscriptSampler.evenlySampled(
                    source,
                    budget: max(4_000, client.chunkCharacterBudget * 3)
                )
            )
        ) else { return nil }

        return LectureStructureParser.parse(raw, as: LectureReview.self)?.normalized()
    }

    /// Applies a review. Returns nil rather than a worse draft: a revision that
    /// came back thinner than what it was given has usually dropped the lecture
    /// instead of correcting it.
    public func revise(
        structure: LectureStructure,
        review: LectureReview,
        briefing: LectureBriefing = .none,
        skills: LectureSkillSet = .standard,
        format: NoteFormatPreferences = .standard
    ) async -> LectureStructure? {
        guard let raw = try? await client.complete(
            system: LecturePrompts.revisionSystem(skills: skills, briefing: briefing, format: format),
            user: LecturePrompts.revisionUser(structure: structure, review: review)
        ) else { return nil }

        guard let revised = LectureStructureParser.parse(raw) else { return nil }
        // Removing noise legitimately makes notes smaller, so the floor here is
        // looser than consolidation's — but a draft that lost most of itself
        // was not corrected, it was replaced.
        guard isAtLeastAsRich(revised, as: structure, ratio: 0.5) else { return nil }
        return revised
    }

    public func makeQuiz(
        structure: LectureStructure,
        skills: LectureSkillSet = .standard
    ) async -> [LectureQuizQuestion]? {
        guard let raw = try? await client.complete(
            system: LecturePrompts.quizSystem(skills: skills),
            user: LecturePrompts.quizUser(structure: structure)
        ) else { return nil }
        return LectureStructureParser.parse(raw, as: LectureQuizSet.self)?.quiz
    }

    /// Asks the model where the finished notes belong.
    ///
    /// Returns nil for anything that cannot be verified against the folders the
    /// model was actually shown, so the caller falls back to token matching. A
    /// wrong answer here files a lecture into someone else's class, which is
    /// worse than a dull-but-correct one.
    public func decidePlacement(
        structure: LectureStructure,
        hint: String?,
        options: [LecturePlacementOption],
        skills: LectureSkillSet = .standard
    ) async -> LectureClassifier.Decision? {
        guard !options.isEmpty else { return nil }
        do {
            let raw = try await client.complete(
                system: LecturePrompts.filingSystem(skills: skills),
                user: LecturePlacementService.user(structure: structure, hint: hint, options: options)
            )
            guard let answer = LectureStructureParser.parse(raw, as: LecturePlacementAnswer.self) else {
                return nil
            }
            return LecturePlacementService.decision(from: answer, options: options)
        } catch {
            return nil
        }
    }

    /// Groups whole pages into model-sized slices, never splitting a page
    /// across two requests unless the page alone exceeds the budget. Keeping
    /// the boundary is what makes "slide 7" citable afterwards.
    func attachmentChunks(for attachments: [LectureAttachmentText]) -> [LectureAttachmentChunk] {
        var built: [LectureAttachmentChunk] = []

        for attachment in attachments {
            // Measure the pages, not the flat text: an attachment whose
            // content lives in its pages would otherwise be dropped whole.
            let contentLength = attachment.effectivePages.reduce(0) { $0 + $1.text.trimmed.count }
            guard contentLength >= 40 else { continue }
            let budget = max(500, client.chunkCharacterBudget)
            var slices: [(first: Int, last: Int, text: String)] = []
            var buffer: [AttachmentTextExtractor.Page] = []
            var length = 0

            func flush() {
                guard let first = buffer.first, let last = buffer.last else { return }
                slices.append((
                    first.number,
                    last.number,
                    buffer.map { "[\(attachment.pageNoun) \($0.number)]\n\($0.text)" }.joined(separator: "\n\n")
                ))
                buffer = []
                length = 0
            }

            for page in attachment.effectivePages {
                let text = page.text.trimmed
                guard !text.isEmpty else { continue }
                if length + text.count > budget, !buffer.isEmpty { flush() }
                if text.count > budget {
                    // A single oversized page is split, and both halves keep
                    // its number so the citation stays accurate.
                    flush()
                    var remainder = Substring(text)
                    while !remainder.isEmpty {
                        let slice = remainder.prefix(budget)
                        slices.append((page.number, page.number, "[\(attachment.pageNoun) \(page.number)]\n\(slice)"))
                        remainder = remainder.dropFirst(slice.count)
                    }
                    continue
                }
                buffer.append(AttachmentTextExtractor.Page(number: page.number, text: text))
                length += text.count
            }
            flush()

            for (offset, slice) in slices.enumerated() {
                built.append(
                    LectureAttachmentChunk(
                        documentName: attachment.name,
                        pageNoun: attachment.pageNoun,
                        firstPage: slice.first,
                        lastPage: slice.last,
                        index: offset,
                        total: slices.count,
                        text: slice.text
                    )
                )
            }
        }
        return built
    }

    func makeChunks(
        segments: [AtlasLectureSegment],
        transcriptText: String,
        durationSeconds: Double
    ) -> [TranscriptChunk] {
        let budget = client.chunkCharacterBudget
        let timed = TranscriptChunker.chunks(from: segments, maximumCharacters: budget)
        guard timed.isEmpty else { return timed }
        return TranscriptChunker.chunks(
            fromPlainText: transcriptText,
            totalDuration: durationSeconds,
            maximumCharacters: budget
        )
    }

    /// Guards against a consolidation pass that silently drops most of the
    /// lecture — a real failure mode when a small model is asked to rewrite a
    /// large object.
    func isAtLeastAsRich(
        _ candidate: LectureStructure,
        as baseline: LectureStructure,
        ratio: Double = 0.5
    ) -> Bool {
        func weight(_ structure: LectureStructure) -> Int {
            structure.keyPoints.count
                + structure.outline.count
                + structure.glossary.count
                + structure.reviewQuestions.count
        }
        return Double(weight(candidate)) >= Double(weight(baseline)) * ratio
    }
}
