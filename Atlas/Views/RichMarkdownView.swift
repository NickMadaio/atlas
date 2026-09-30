import AtlasCore
import SwiftUI

/// Renders one note's Markdown.
///
/// Sized for reading rather than for fitting: body text at 15.5, real space
/// between blocks, and lists that keep the nesting they were written with. The
/// old renderer set body text at `.body` inside 15pt-spaced stacks and
/// flattened every sub-point, which is most of why a page of notes felt cramped.
struct RichMarkdownView: View {
    let source: String
    /// Resolves `![[Title]]` to a note. Absent by default, so the renderer
    /// works anywhere without the library being wired in.
    var resolveEmbed: (String) -> AtlasNoteEmbedSource? = { _ in nil }
    var openEmbed: (AtlasNoteEmbedSource) -> Void = { _ in }
    var embedDepth: Int = 0

    @Environment(\.atlasPalette) private var theme

    /// `[[Title]]` becomes an ordinary Markdown link first, so the inline
    /// renderer turns it into something clickable. `![[Title]]` survives and is
    /// picked up as its own block.
    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(AtlasNoteLinks.resolvingWikiLinks(in: source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.step) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            InlineMarkdownText(source: text, size: headingSize(level), weight: .bold)
                .font(AtlasType.display(headingSize(level), .bold))
                .foregroundStyle(level <= 3 ? theme.textPrimary : theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 3 ? AtlasSpace.tight : 2)

        case let .paragraph(text):
            InlineMarkdownText(source: text)
                .font(AtlasType.body())
                .foregroundStyle(theme.textPrimary.opacity(0.92))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

        case let .list(list):
            listView(list, level: 0)

        case let .quote(text):
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 2).fill(theme.primary).frame(width: 3)
                InlineMarkdownText(source: text, size: 15, weight: .medium)
                    .font(AtlasType.body(15, .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

        case let .code(language, code):
            AtlasCodeBlock(language: language, code: code)

        case let .table(headers, rows):
            markdownTable(headers: headers, rows: rows)

        case .divider:
            AtlasFadingRule().padding(.vertical, AtlasSpace.hair)

        case let .callout(kind, text):
            AtlasCalloutView(kind: kind, text: text)

        case let .sketch(id):
            SketchEmbedView(id: id)

        case let .embed(title):
            if embedDepth >= 1 {
                // Deeper than one level, a reference rather than an unfold.
                AtlasInlineAction(title: title, systemImage: "arrow.up.right", tint: theme.highlight) {
                    if let source = resolveEmbed(title) { openEmbed(source) }
                }
            } else {
                NoteEmbedView(title: title, resolve: resolveEmbed, open: openEmbed, depth: embedDepth)
            }
        }
    }

    // MARK: - Lists

    /// Sub-points indent and change marker, the way a slide deck writes them:
    /// a filled dot at the top level, a ring below it.
    @ViewBuilder
    private func listView(_ list: MarkdownList, level: Int) -> some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        marker(for: item, list: list, index: index, level: level)
                        InlineMarkdownText(source: item.text)
                            .font(AtlasType.body())
                            .foregroundStyle(theme.textPrimary.opacity(level == 0 ? 0.92 : 0.8))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sublist = item.sublist {
                        // Erased because the nesting is genuinely recursive,
                        // and an opaque type cannot be defined in terms of
                        // itself.
                        AnyView(listView(sublist, level: level + 1))
                            .padding(.leading, 26)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, list: MarkdownList, index: Int, level: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(checked ? theme.primary : theme.textSecondary)
                .frame(width: 18, alignment: .leading)
        } else if list.ordered {
            Text("\(index + 1).")
                .font(AtlasType.mono(13, .bold))
                .foregroundStyle(theme.primary)
                .frame(width: 22, alignment: .leading)
        } else if level == 0 {
            Circle()
                .fill(theme.primary)
                .frame(width: 6, height: 6)
                .frame(width: 18, alignment: .leading)
                .offset(y: -1)
        } else {
            Circle()
                .stroke(theme.textSecondary, lineWidth: 1.4)
                .frame(width: 6, height: 6)
                .frame(width: 18, alignment: .leading)
                .offset(y: -1)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 24
        case 2: 20
        case 3: 17
        default: 15
        }
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> some View {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        return ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { index in
                        InlineMarkdownText(source: headers[safe: index] ?? "", size: 13, weight: .bold)
                            .font(AtlasType.body(13, .bold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(minWidth: 150, maxWidth: 260, minHeight: 46, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(theme.tintSurface)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { index in
                            InlineMarkdownText(source: row[safe: index] ?? "", size: 13.5)
                                .font(AtlasType.body(13.5))
                                .foregroundStyle(theme.textSecondary)
                                .frame(minWidth: 150, maxWidth: 260, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(rowIndex.isMultiple(of: 2) ? theme.surface : theme.surfaceRaised)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.divider, lineWidth: 1) }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
