import AtlasCore
import Combine
import Foundation

/*
 Everything about how Atlas writes notes, in one place a person can reach.

 These used to be constants in the source. That made them invisible: when notes
 came out wrong there was nothing to turn, and the only fix was to ask someone
 to change the app. They are device preferences, not library data — they belong
 in UserDefaults rather than in the SwiftData store, so no note is at risk from
 an edit here.
*/
@MainActor
final class AtlasSettingsStore: ObservableObject {

    /// The model's instructions, as five editable files.
    @Published var skills: LectureSkillSet {
        didSet { defaults.set(skills.encoded, forKey: Keys.skills) }
    }

    /// How a finished note is laid out.
    @Published var noteFormat: NoteFormatPreferences {
        didSet { defaults.set(noteFormat.encoded, forKey: Keys.noteFormat) }
    }

    /// Which Ollama model to prefer, when more than one is installed. Empty
    /// means "whichever Atlas judges best", which is the right default.
    @Published var preferredModel: String {
        didSet {
            let clean = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                defaults.removeObject(forKey: Keys.preferredModel)
            } else {
                defaults.set(clean, forKey: Keys.preferredModel)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skills = LectureSkillSet.decoded(defaults.string(forKey: Keys.skills) ?? "{}")
        noteFormat = NoteFormatPreferences.decoded(defaults.string(forKey: Keys.noteFormat) ?? "")
        preferredModel = defaults.string(forKey: Keys.preferredModel) ?? ""
    }

    // MARK: - Editing

    func setInstructions(_ text: String, for skill: LectureSkill) {
        skills = skills.setting(text, for: skill)
    }

    func resetInstructions(for skill: LectureSkill) {
        skills = skills.resetting(skill)
    }

    func resetAllInstructions() {
        skills = .standard
    }

    func setSection(_ section: NoteFormatPreferences.Section, included: Bool) {
        noteFormat = noteFormat.setting(section, to: included)
    }

    func resetNoteFormat() {
        noteFormat = .standard
    }

    /// True when anything here differs from what Atlas ships with, so the
    /// interface can say so rather than making people compare by eye.
    var hasChanges: Bool {
        !skills.customisedSkills.isEmpty || noteFormat != .standard || !preferredModel.isEmpty
    }

    private enum Keys {
        static let skills = "atlas.lecture.skills"
        static let noteFormat = "atlas.lecture.noteFormat"
        /// Shared with the model resolver, which reads it directly so a lecture
        /// started from the menu bar honours the same choice.
        static let preferredModel = "atlas.lecture.preferredOllamaModel"
    }
}
