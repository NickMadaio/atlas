import AtlasCore
import SwiftUI

/// A note that another note pulls in.
///
/// The Obsidian idea, with one deliberate difference: it arrives folded. A
/// lecture note is meant to be readable top to bottom, and three fully expanded
/// work-throughs inside it make it unreadable — so the headline and the
/// one-line summary carry the meaning, and the full explanation opens where it
/// sits when you want it. Nothing is hidden behind a click you have to guess at.
struct AtlasNoteEmbedSource: Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let markdown: String

    init(_ document: AtlasDocumentSnapshot) {
        id = document.id
        title = document.title
        summary = document.summary
        markdown = document.bodyMarkdown
    }
}

struct NoteEmbedView: View {
    let title: String
    let resolve: (String) -> AtlasNoteEmbedSource?
    let open: (AtlasNoteEmbedSource) -> Void
    /// How many embeds deep this already is. Past the first level an embed
    /// renders as a link instead, so a note that references itself, directly or
    /// in a ring, cannot recurse forever.
    var depth: Int = 0

    @State private var isExpanded = false
    @Environment(\.atlasPalette) private var theme

    private var source: AtlasNoteEmbedSource? { resolve(title) }

    var body: some View {
        if let source {
            AtlasPanel(accent: theme.highlight) {
                VStack(alignment: .leading, spacing: isExpanded ? AtlasSpace.step : AtlasSpace.hair) {
                    header(source)
                    if isExpanded {
                        AtlasFadingRule(tint: theme.highlight)
                        // Erased: a note can embed a note, so the two view
                        // types refer to each other and neither can be opaque.
                        AnyView(
                            RichMarkdownView(
                                source: source.markdown,
                                resolveEmbed: resolve,
                                openEmbed: open,
                                embedDepth: depth + 1
                            )
                        )
                    } else if !source.summary.isEmpty {
                        Text(source.summary)
                            .font(AtlasType.body(14))
                            .foregroundStyle(theme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            // Naming what is missing beats a silent gap: the link was written
            // by a model, and a note it expected can be renamed or deleted.
            HStack(spacing: 8) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 12))
                Text("\(title) — this note is not in your library.")
                    .font(AtlasType.body(13.5))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.vertical, 4)
        }
    }

    private func header(_ source: AtlasNoteEmbedSource) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(theme.highlight)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    VStack(alignment: .leading, spacing: 4) {
                        AtlasMicroLabel(text: depth > 0 ? "note" : "in depth", tint: theme.highlight, size: 9.5)
                        Text(source.title)
                            .font(AtlasType.display(17, .bold))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            AtlasInlineAction(
                title: "Open",
                systemImage: "arrow.up.right",
                tint: theme.highlight
            ) { open(source) }
            .fixedSize()
        }
    }
}
