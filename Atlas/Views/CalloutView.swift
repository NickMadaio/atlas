import AtlasCore
import SwiftUI

/// A set-aside block: `> [!answer] …`, `> [!note] …`.
///
/// The `answer` kind is the reason this exists. A quiz whose answers sit
/// underneath the questions is not a quiz, it is a list of facts — but an
/// answer kept somewhere else is an answer you never find again. Folded into
/// the note, one tap away, is the only arrangement that is both.
struct AtlasCalloutView: View {
    let kind: String
    let text: String

    @State private var isRevealed = false
    @Environment(\.atlasPalette) private var theme

    private var isAnswer: Bool { kind == "answer" }

    private var tint: Color {
        switch kind {
        case "answer": theme.primary
        case "warning", "caution": theme.warmAccent
        case "danger", "error": theme.danger
        default: theme.highlight
        }
    }

    private var symbol: String {
        switch kind {
        case "answer": "key.fill"
        case "warning", "caution": "exclamationmark.triangle"
        case "danger", "error": "xmark.octagon"
        case "tip": "lightbulb"
        default: "info.circle"
        }
    }

    var body: some View {
        if isAnswer, !isRevealed {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isRevealed = true }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "eye")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Show answer")
                        .font(AtlasType.mono(11.5, .semibold))
                        .tracking(0.6)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .overlay {
                    Capsule().stroke(tint, lineWidth: 1.2)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 2)
                InlineMarkdownText(source: text, size: 14.5)
                    .font(AtlasType.body(14.5))
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(theme.tintSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 10)
            }
        }
    }
}
