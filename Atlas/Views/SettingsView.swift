import AtlasCore
import SwiftUI

/*
 Settings, including the part that used to be unreachable.

 Three of these four tabs are ordinary preferences. The fourth — Instructions —
 is the model's own brain: the five files that decide what Atlas knows before it
 writes, how it writes, how it reads your slides, how it merges an hour of
 transcript, and where the finished notes go. They were constants in the source,
 which meant that when notes came out wrong there was nothing to turn.

 They are shown in the order they actually run, because that order is the thing
 people get wrong about prompt editing: context first, filing last.
*/
struct AtlasSettingsView: View {
    @ObservedObject var settings: AtlasSettingsStore
    @ObservedObject var appearance: AtlasAppearanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme

    enum Tab: String, CaseIterable, Identifiable {
        case notes, instructions, model, appearance
        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: "Notes"
            case .instructions: "Instructions"
            case .model: "Local model"
            case .appearance: "Appearance"
            }
        }

        var symbol: String {
            switch self {
            case .notes: "doc.text"
            case .instructions: "brain"
            case .model: "cpu"
            case .appearance: "circle.lefthalf.filled"
            }
        }

        var subtitle: String {
            switch self {
            case .notes: "what a lecture note contains"
            case .instructions: "what the model is told"
            case .model: "which model writes them"
            case .appearance: "colour and mark"
            }
        }
    }

    @State private var tab: Tab = .notes
    @State private var installedModels: [String] = []

    var body: some View {
        HStack(spacing: 0) {
            tabColumn
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AtlasSpace.block) {
                    switch tab {
                    case .notes: NoteFormatSettings(settings: settings)
                    case .instructions: SkillSettings(settings: settings)
                    case .model: modelSettings
                    case .appearance: AppearanceSettings(store: appearance)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, AtlasSpace.gutter)
                .padding(.vertical, AtlasSpace.block)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.canvas)
        }
        .frame(minWidth: 940, minHeight: 640)
        .background(theme.canvas)
        .presentationBackground(theme.canvas)
        .task {
#if os(macOS)
            installedModels = await LectureModelResolver.availableModelNames()
#endif
        }
    }

    private var tabColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(AtlasType.display(23, .bold))
                    .foregroundStyle(theme.textPrimary)
                AtlasMicroLabel(text: "how atlas works", size: 9)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, AtlasSpace.step)

            ForEach(Tab.allCases) { candidate in
                Button { tab = candidate } label: {
                    HStack(spacing: 12) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == candidate ? theme.primary : theme.textSecondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title)
                                .font(AtlasType.body(14, tab == candidate ? .bold : .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(candidate.subtitle)
                                .font(AtlasType.mono(9.5))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(alignment: .leading) {
                        if tab == candidate {
                            LinearGradient(
                                colors: [theme.primary.opacity(0.20), theme.primary.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            HStack {
                if settings.hasChanges {
                    AtlasStateTag(text: "changed from default", tint: theme.warmAccent)
                }
                Spacer(minLength: 0)
                AtlasSolidAction(title: "Done") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 268)
        .background(theme.sidebar)
    }

    // MARK: - Model

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.step) {
            SettingsHeader(
                title: "Local model",
                detail: "Notes are written on this Mac. Atlas prefers Ollama when it is running, falls back to Apple's on-device model, and writes transcript-only notes when neither is there. Lecture text is never sent off this machine."
            )

#if !os(macOS)
            Text("Lectures are recorded and written on the Mac. This is where that model is chosen.")
                .font(AtlasType.body(14))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
#endif
            if installedModels.isEmpty {
                Text("Ollama is not running, or has no models installed. Atlas will use Apple's on-device model.")
                    .font(AtlasType.body(14))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Preferred model", selection: $settings.preferredModel) {
                    Text("Let Atlas choose").tag("")
                    ForEach(installedModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text("A bigger model writes noticeably better notes and takes noticeably longer.")
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

// MARK: - Shared pieces

struct SettingsHeader: View {
    let title: String
    let detail: String
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.hair) {
            Text(title)
                .font(AtlasType.display(20, .bold))
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(AtlasType.body(14))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AtlasType.body(14.5, .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(AtlasType.body(13))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 9)
    }
}
