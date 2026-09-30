import Foundation

/// One question a student can test themselves with.
///
/// The answer is stored beside the question rather than in a separate list, so
/// nothing can drift out of order, and the renderer is what decides to hide it.
public struct LectureQuizQuestion: Codable, Hashable, Sendable {
    public var question: String
    /// Optional multiple choice. Empty means it is a written answer.
    public var options: [String]
    public var answer: String
    /// One line on why, so a wrong answer teaches something.
    public var explanation: String
    /// "lecture", "slides", or "both" — which source the question came from.
    /// A quiz drawn only from slides tests reading, not attendance.
    public var source: String

    public init(
        question: String,
        options: [String] = [],
        answer: String,
        explanation: String = "",
        source: String = ""
    ) {
        self.question = question
        self.options = options
        self.answer = answer
        self.explanation = explanation
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = container.lenientString(.question)
        options = container.lenientStrings(.options)
        answer = container.lenientString(.answer)
        explanation = container.lenientString(.explanation)
        source = container.lenientString(.source)
    }
}

/// Something the class did rather than was told.
///
/// A recording of a room does not pause for group work. Ninety minutes of
/// marketing contains several minutes of students talking over each other about
/// IKEA, none of which is what the lecturer taught — but the activity itself,
/// and whatever the lecturer concluded from it, is worth keeping. Recording it
/// as an activity is what lets the crosstalk be thrown away without losing the
/// fact that it happened.
public struct LectureActivity: Codable, Hashable, Sendable {
    public var title: String
    /// What the class was asked to do.
    public var task: String
    /// What the lecturer drew out of it afterwards, if anything.
    public var conclusion: String
    /// Rough position in the recording, if the model could tell.
    public var whenLabel: String

    public init(title: String, task: String = "", conclusion: String = "", whenLabel: String = "") {
        self.title = title
        self.task = task
        self.conclusion = conclusion
        self.whenLabel = whenLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenientString(.title)
        task = container.lenientString(.task)
        conclusion = container.lenientString(.conclusion)
        whenLabel = container.lenientString(.whenLabel)
    }
}

/// One thing a review pass found wrong with a draft.
public struct LectureCorrection: Codable, Hashable, Sendable {
    /// What is wrong, quoted or described well enough to find.
    public var problem: String
    /// Which kind, so the revision pass knows what to do about it:
    /// "unsupported", "noise", "duplicate", "misattributed", "garbled", "missing".
    public var kind: String
    /// What it should say instead, or empty to mean "remove it".
    public var correction: String

    public init(problem: String, kind: String = "", correction: String = "") {
        self.problem = problem
        self.kind = kind
        self.correction = correction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        problem = container.lenientString(.problem)
        kind = container.lenientString(.kind)
        correction = container.lenientString(.correction)
    }
}

/// What a review pass returns.
public struct LectureReview: Codable, Hashable, Sendable {
    public var corrections: [LectureCorrection]

    public init(corrections: [LectureCorrection] = []) {
        self.corrections = corrections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        corrections = container.lenientList(LectureCorrection.self, .corrections)
    }

    /// Bounded and de-duplicated. A model asked to criticise will keep going.
    public func normalized() -> LectureReview {
        var seen = Set<String>()
        return LectureReview(
            corrections: corrections
                .map {
                    LectureCorrection(
                        problem: $0.problem.keyboardNormalized.trimmed.bounded(400),
                        kind: $0.kind.trimmed.lowercased().bounded(20),
                        correction: $0.correction.keyboardNormalized.trimmed.bounded(600)
                    )
                }
                .filter { !$0.problem.isEmpty && seen.insert($0.problem.lowercased()).inserted }
                .prefix(20)
                .map { $0 }
        )
    }
}

/// The quiz on its own, so the pass that writes it returns only that.
public struct LectureQuizSet: Codable, Hashable, Sendable {
    public var quiz: [LectureQuizQuestion]

    public init(quiz: [LectureQuizQuestion] = []) {
        self.quiz = quiz
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quiz = container.lenientList(LectureQuizQuestion.self, .quiz)
    }
}
