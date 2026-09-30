import AtlasCore
import SwiftUI

/// What a lecture note contains, and how much of it.
struct NoteFormatSettings: View {
    @ObservedObject var settings: AtlasSettingsStore
    @Environment(\.atlasPalette) private var theme

    private var reviewExplanation: String {
        switch settings.noteFormat.reviewPasses {
        case 0: "Whatever the model writes first is what you get."
        case 1: "The draft is read back once and corrected. Recommended."
        default: "Read back twice. For a recording you know was messy — a long class with activities in it."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.block) {
            SettingsHeader(
                title: "Notes",
                detail: "How a lecture note is laid out. Changing anything here changes the next set of notes — use Rewrite notes on a recording to apply it to one you already have."
            )

            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                AtlasSectionRule(title: "how much detail")
                Picker("Detail", selection: $settings.noteFormat.detail) {
                    ForEach(NoteFormatPreferences.Detail.allCases) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(settings.noteFormat.detail.subtitle)
                    .font(AtlasType.body(13))
                    .foregroundStyle(theme.textSecondary)
                // Stated plainly because it is the surprising part: this
                // changes what the model is asked for, not just what is shown.
                Text("This is sent to the model, so it writes to this length rather than being cut down to it.")
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                AtlasSectionRule(title: "sections")
                    .padding(.bottom, AtlasSpace.hair)
                ForEach(NoteFormatPreferences.Section.allCases) { section in
                    SettingsToggleRow(
                        title: section.title,
                        subtitle: section.subtitle,
                        isOn: Binding(
                            get: { settings.noteFormat.includes(section) },
                            set: { settings.setSection(section, included: $0) }
                        )
                    )
                    AtlasFadingRule()
                }
            }

            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                AtlasSectionRule(title: "checking the notes")
                Picker("Review passes", selection: $settings.noteFormat.reviewPasses) {
                    Text("Off").tag(0)
                    Text("One pass").tag(1)
                    Text("Two passes").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(reviewExplanation)
                    .font(AtlasType.body(13))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each pass reads the draft back against the transcript and lists what is wrong, then applies it. It is the only thing that reliably catches group work being written up as content. It also costs a couple of minutes per lecture.")
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                AtlasSectionRule(title: "companion notes")
                    .padding(.bottom, AtlasSpace.hair)
                SettingsToggleRow(
                    title: "Open in place",
                    subtitle: "When one idea gets a note of its own, it unfolds inside the section that mentions it. Turn this off to leave a link instead.",
                    isOn: $settings.noteFormat.embedsCompanions
                )
                AtlasFadingRule()
            }

            HStack {
                Spacer(minLength: 0)
                AtlasInlineAction(title: "Reset to defaults", tint: theme.textSecondary) {
                    settings.resetNoteFormat()
                }
            }
        }
    }
}

/// The five instruction files, in the order they run.
struct SkillSettings: View {
    @ObservedObject var settings: AtlasSettingsStore
    @Environment(\.atlasPalette) private var theme
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.step) {
            SettingsHeader(
                title: "Instructions",
                detail: "These are the exact words the local model is given at each stage. Edit one and the next set of notes is written differently. They run in the order below."
            )

            Text("Atlas adds the JSON shape it needs on top of these, so an edit cannot break note writing by leaving it out.")
                .font(AtlasType.mono(10.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(LectureSkill.allCases.enumerated()), id: \.element.id) { index, skill in
                    SkillRow(
                        skill: skill,
                        order: index + 1,
                        settings: settings,
                        isExpanded: Binding(
                            get: { expanded.contains(skill.rawValue) },
                            set: { open in
                                if open { expanded.insert(skill.rawValue) } else { expanded.remove(skill.rawValue) }
                            }
                        )
                    )
                }
            }

            if !settings.skills.customisedSkills.isEmpty {
                HStack {
                    Text(settings.skills.customisedSkills.count == 1
                         ? "1 file has been edited."
                         : "\(settings.skills.customisedSkills.count) files have been edited.")
                        .font(AtlasType.body(13))
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 0)
                    AtlasInlineAction(title: "Reset all", isDestructive: true) {
                        settings.resetAllInstructions()
                    }
                }
            }
        }
    }
}

private struct SkillRow: View {
    let skill: LectureSkill
    let order: Int
    @ObservedObject var settings: AtlasSettingsStore
    @Binding var isExpanded: Bool

    @State private var draft = ""
    @Environment(\.atlasPalette) private var theme

    private var isCustomised: Bool { settings.skills.isCustomised(skill) }

    var body: some View {
        AtlasExpandingRow(
            title: "\(order). \(skill.title)",
            caption: skill.whenItRuns,
            accent: isCustomised ? theme.warmAccent : theme.primary,
            trailing: isCustomised ? "edited" : nil,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                TextEditor(text: $draft)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 260)
                    .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.divider, lineWidth: 1)
                    }

                HStack(spacing: AtlasSpace.step) {
                    AtlasSolidAction(title: "Save") {
                        settings.setInstructions(draft, for: skill)
                    }
                    .disabled(draft == settings.skills.instructions(for: skill))

                    if isCustomised {
                        AtlasInlineAction(title: "Restore default", tint: theme.textSecondary) {
                            settings.resetInstructions(for: skill)
                            draft = skill.defaultInstructions
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(draft.count) / \(LectureSkillSet.maximumInstructionCharacters)")
                        .font(AtlasType.mono(10))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.trailing, 4)
        }
        // Loaded when the row opens rather than held for every file at once,
        // and reloaded if the stored text changes underneath.
        .task(id: "\(skill.rawValue)-\(isExpanded)") {
            guard isExpanded else { return }
            draft = settings.skills.instructions(for: skill)
        }
    }
}

/// Appearance, unchanged in substance and rebuilt to match everything else.
struct AppearanceSettings: View {
    @ObservedObject var store: AtlasAppearanceStore
    @Environment(\.atlasPalette) private var theme
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.block) {
            SettingsHeader(
                title: "Appearance",
                detail: "Device-local. None of this is stored with your notes or sent anywhere."
            )

            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                AtlasSectionRule(title: "light and dark")
                Picker("Appearance", selection: $store.mode) {
                    ForEach(AtlasAppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if store.colorTheme.forcesDarkMode {
                    Text("Orion is a dark palette, so it stays dark whatever is chosen here.")
                        .font(AtlasType.mono(10))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                AtlasSectionRule(title: "colour")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AtlasColorTheme.allCases) { choice in
                        themeChoice(choice)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                AtlasSectionRule(title: "atlas mark")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AtlasLogoStyle.allCases) { style in
                        logoChoice(style)
                    }
                }
            }
        }
    }

    private func themeChoice(_ colorTheme: AtlasColorTheme) -> some View {
        let preview = AtlasPalette.palette(for: colorTheme)
        let selected = store.colorTheme == colorTheme
        return Button { store.colorTheme = colorTheme } label: {
            HStack(spacing: 14) {
                HStack(spacing: -9) {
                    Circle().fill(preview.primaryStrong).frame(width: 30, height: 30)
                    Circle().fill(preview.primary).frame(width: 30, height: 30)
                    Circle().fill(preview.warmAccent).frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(colorTheme.title)
                        .font(AtlasType.body(14.5, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(colorTheme.subtitle)
                        .font(AtlasType.body(12.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? theme.primary : theme.textSecondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(selected ? theme.tintSurface : theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(selected ? theme.primary : theme.divider, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func logoChoice(_ style: AtlasLogoStyle) -> some View {
        let selected = store.logoStyle == style
        return Button { store.logoStyle = style } label: {
            HStack(spacing: 14) {
                AtlasLogo(size: 50).environment(\.atlasLogoStyle, style)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title)
                        .font(AtlasType.body(14.5, .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(style.subtitle)
                        .font(AtlasType.body(12.5))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 6)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? theme.primary : theme.textSecondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(selected ? theme.tintSurface : theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(selected ? theme.primary : theme.divider, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
