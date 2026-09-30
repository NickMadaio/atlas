import AtlasCore
import SwiftUI

#if os(macOS)

/// The raw transcript, readable and correctable.
///
/// Automatic transcription mishears technical vocabulary, and a wrong term
/// propagates into every note written from it. Fixing the word here and
/// rewriting is far quicker than correcting two notes by hand.
struct LectureTranscriptView: View {
    let lecture: AtlasLectureSnapshot
    let onSave: (String) -> Void
    let onSaveAndRewrite: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var text: String

    init(
        lecture: AtlasLectureSnapshot,
        onSave: @escaping (String) -> Void,
        onSaveAndRewrite: @escaping (String) -> Void
    ) {
        self.lecture = lecture
        self.onSave = onSave
        self.onSaveAndRewrite = onSaveAndRewrite
        _text = State(initialValue: lecture.transcriptText)
    }

    private var isValid: Bool { text.count <= 1_000_000 }
    private var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "text.quote",
            title: "Transcript",
            subtitle: "\(lecture.titleGuess) · \(lecture.durationLabel)",
            confirmTitle: "Save & rewrite notes",
            isConfirmEnabled: isValid,
            secondaryTitle: "Save only",
            onSecondary: { if isValid { onSave(text) } },
            onCancel: { dismiss() },
            onConfirm: { if isValid { onSaveAndRewrite(text) } }
        ) {
            AtlasField(label: "What Atlas heard", hint: "\(wordCount) words") {
                TextEditor(text: $text)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 340)
                    .padding(9)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.divider, lineWidth: 1)
                    }
                    .accessibilityLabel("Lecture transcript")
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                Text(noteText)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .atlasSheetFrame(macWidth: 660, minHeight: 560)
        .presentationBackground(.clear)
    }

    private var noteText: String {
        if lecture.segments.isEmpty {
            return "Rewriting replaces both notes for this lecture from the text above. The audio is kept either way."
        }
        return "Editing drops the timecodes, since they would no longer line up with the words. Rewriting then rebuilds both notes from your corrected text. The audio is kept either way."
    }
}

#endif
