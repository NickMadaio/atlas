import Foundation

/*
 How a lecture note is laid out.

 These used to be decisions baked into the builder, visible only as the shape
 of the notes that came out. They are choices, so they belong somewhere a person
 can change them — and changing one and pressing Rewrite is how you find out
 what you actually want your notes to look like.
*/
public struct NoteFormatPreferences: Codable, Hashable, Sendable {

    /// How much the model is asked for, and how much is rendered.
    public enum Detail: String, Codable, Sendable, CaseIterable, Identifiable {
        case tight, standard, full
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .tight: "Tight"
            case .standard: "Standard"
            case .full: "Full"
            }
        }

        public var subtitle: String {
            switch self {
            case .tight: "The shortest notes that still hold the lecture."
            case .standard: "What most lectures need."
            case .full: "Everything, including the parts you may not reread."
            }
        }

        /// Guidance appended to the writing instructions. The model's own
        /// output changes, not just what is rendered — trimming a full set of
        /// notes down afterwards wastes the work and reads as truncated.
        public var writingGuidance: String {
            switch self {
            case .tight:
                "Keep this tight. Prefer few, strong bullets over many weak ones. Define only "
                    + "terms a student would otherwise have to look up."
            case .standard:
                "Aim for notes a student could revise from without the recording."
            case .full:
                "Be thorough. Define every term the lecturer used as though it were new, and "
                    + "keep detail a student might want in three months."
            }
        }

        public var keyPointLimit: Int {
            switch self {
            case .tight: 8
            case .standard: 14
            case .full: 20
            }
        }

        public var glossaryLimit: Int {
            switch self {
            case .tight: 8
            case .standard: 18
            case .full: 30
            }
        }
    }

    public var detail: Detail
    public var includesKeyPoints: Bool
    public var includesOutline: Bool
    public var includesGlossary: Bool
    public var includesFormulas: Bool
    public var includesReviewQuestions: Bool
    public var includesOtherVoices: Bool
    public var includesFollowUps: Bool
    /// What the class did rather than was told.
    public var includesActivities: Bool
    /// A short quiz written from the finished notes.
    public var includesQuiz: Bool
    /// How many times the draft is read back and corrected before it is kept.
    /// Zero is the old behaviour; one catches most of what leaks in from group
    /// work; two is for a recording you know was messy.
    public var reviewPasses: Int
    /// Whether a companion note opens inside the section that references it,
    /// or is only a link out.
    public var embedsCompanions: Bool
    /// The "Recording" footer: date, length, what wrote the notes.
    public var includesRecordingDetails: Bool

    public init(
        detail: Detail = .standard,
        includesKeyPoints: Bool = true,
        includesOutline: Bool = true,
        includesGlossary: Bool = true,
        includesFormulas: Bool = true,
        includesReviewQuestions: Bool = true,
        includesOtherVoices: Bool = true,
        includesFollowUps: Bool = true,
        includesActivities: Bool = true,
        includesQuiz: Bool = true,
        reviewPasses: Int = 1,
        embedsCompanions: Bool = true,
        includesRecordingDetails: Bool = true
    ) {
        self.detail = detail
        self.includesKeyPoints = includesKeyPoints
        self.includesOutline = includesOutline
        self.includesGlossary = includesGlossary
        self.includesFormulas = includesFormulas
        self.includesReviewQuestions = includesReviewQuestions
        self.includesOtherVoices = includesOtherVoices
        self.includesFollowUps = includesFollowUps
        self.includesActivities = includesActivities
        self.includesQuiz = includesQuiz
        self.reviewPasses = min(max(reviewPasses, 0), 2)
        self.embedsCompanions = embedsCompanions
        self.includesRecordingDetails = includesRecordingDetails
    }

    public static let standard = NoteFormatPreferences()

    /// Sections the reader can turn off, for a settings list that does not have
    /// to be edited every time one is added.
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case keyPoints, outline, glossary, formulas, reviewQuestions, quiz, activities, otherVoices, followUps, recordingDetails
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .keyPoints: "Key points"
            case .outline: "Outline"
            case .glossary: "Terms to know"
            case .formulas: "Formulas"
            case .reviewQuestions: "Questions to review"
            case .quiz: "Test yourself"
            case .activities: "In class"
            case .otherVoices: "From the room"
            case .followUps: "Follow-ups"
            case .recordingDetails: "Recording details"
            }
        }

        public var subtitle: String {
            switch self {
            case .keyPoints: "The things worth remembering, as a list."
            case .outline: "The lecture in the order it was taught."
            case .glossary: "Short definitions, with the long ones a click away."
            case .formulas: "Anything written as an expression."
            case .reviewQuestions: "Open questions to think through."
            case .quiz: "Five to ten questions with the answers hidden until you ask."
            case .activities: "Group work and discussions, summarised rather than transcribed."
            case .otherVoices: "What people other than the lecturer said."
            case .followUps: "Anything you were told to do."
            case .recordingDetails: "When it was recorded, how long, what wrote it."
            }
        }
    }

    public func includes(_ section: Section) -> Bool {
        switch section {
        case .keyPoints: includesKeyPoints
        case .outline: includesOutline
        case .glossary: includesGlossary
        case .formulas: includesFormulas
        case .reviewQuestions: includesReviewQuestions
        case .quiz: includesQuiz
        case .activities: includesActivities
        case .otherVoices: includesOtherVoices
        case .followUps: includesFollowUps
        case .recordingDetails: includesRecordingDetails
        }
    }

    public func setting(_ section: Section, to value: Bool) -> NoteFormatPreferences {
        var copy = self
        switch section {
        case .keyPoints: copy.includesKeyPoints = value
        case .outline: copy.includesOutline = value
        case .glossary: copy.includesGlossary = value
        case .formulas: copy.includesFormulas = value
        case .reviewQuestions: copy.includesReviewQuestions = value
        case .quiz: copy.includesQuiz = value
        case .activities: copy.includesActivities = value
        case .otherVoices: copy.includesOtherVoices = value
        case .followUps: copy.includesFollowUps = value
        case .recordingDetails: copy.includesRecordingDetails = value
        }
        return copy
    }

    // MARK: - Persistence

    public var encoded: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    public static func decoded(_ json: String) -> NoteFormatPreferences {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(NoteFormatPreferences.self, from: data) else {
            return .standard
        }
        return value
    }

    /// Settings saved before these fields existed decode as missing rather than
    /// as false, so they take the shipped default instead of silently turning
    /// new sections off.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = NoteFormatPreferences.standard
        detail = (try? container.decodeIfPresent(Detail.self, forKey: .detail)) ?? fallback.detail
        includesKeyPoints = (try? container.decodeIfPresent(Bool.self, forKey: .includesKeyPoints)) ?? fallback.includesKeyPoints
        includesOutline = (try? container.decodeIfPresent(Bool.self, forKey: .includesOutline)) ?? fallback.includesOutline
        includesGlossary = (try? container.decodeIfPresent(Bool.self, forKey: .includesGlossary)) ?? fallback.includesGlossary
        includesFormulas = (try? container.decodeIfPresent(Bool.self, forKey: .includesFormulas)) ?? fallback.includesFormulas
        includesReviewQuestions = (try? container.decodeIfPresent(Bool.self, forKey: .includesReviewQuestions)) ?? fallback.includesReviewQuestions
        includesOtherVoices = (try? container.decodeIfPresent(Bool.self, forKey: .includesOtherVoices)) ?? fallback.includesOtherVoices
        includesFollowUps = (try? container.decodeIfPresent(Bool.self, forKey: .includesFollowUps)) ?? fallback.includesFollowUps
        includesActivities = (try? container.decodeIfPresent(Bool.self, forKey: .includesActivities)) ?? fallback.includesActivities
        includesQuiz = (try? container.decodeIfPresent(Bool.self, forKey: .includesQuiz)) ?? fallback.includesQuiz
        embedsCompanions = (try? container.decodeIfPresent(Bool.self, forKey: .embedsCompanions)) ?? fallback.embedsCompanions
        includesRecordingDetails = (try? container.decodeIfPresent(Bool.self, forKey: .includesRecordingDetails)) ?? fallback.includesRecordingDetails
        let passes = (try? container.decodeIfPresent(Int.self, forKey: .reviewPasses)) ?? fallback.reviewPasses
        reviewPasses = min(max(passes, 0), 2)
    }
}
