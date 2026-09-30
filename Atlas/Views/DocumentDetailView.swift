import AtlasCore
import SwiftUI

/// One note, read.
///
/// Each `##` section becomes its own panel, because a page of lecture notes is
/// a run of separate ideas and the reader has to see where one ends — the same
/// shape the course's own pages use. Companion notes open inside the section
/// that references them rather than sitting in a list at the bottom.
struct DocumentDetailView: View {
    let document: AtlasDocumentSnapshot
    /// Notes that hang off this one, including the assistant's source file.
    let children: [AtlasDocumentSnapshot]
    /// The note you came from, when you followed a link to get here.
    let backTitle: String?
    /// Section to scroll to on arrival — where you were when you left.
    let anchorSection: String?
    let onBack: () -> Void
    let onEdit: () -> Void
    let onFavorite: () -> Void
    /// Opens another note, remembering which section of this one you left from.
    let onOpen: (AtlasDocumentSnapshot, String?) -> Void
    /// Resolves a `[[Title]]` reference to a note, if one exists.
    let resolveLink: (String) -> AtlasDocumentSnapshot?

    @Environment(\.atlasPalette) private var theme
    @State private var showsLinked = false

    private var sections: [AtlasSection] {
        MarkdownSections.parse(document.bodyMarkdown)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AtlasSpace.block) {
                    if let backTitle { backRow(backTitle) }
                    header
                    if !children.isEmpty { linkedNotes }
                    if sections.count > 1 { sectionNavigator(proxy: proxy) }

                    VStack(alignment: .leading, spacing: AtlasSpace.section) {
                        ForEach(sections) { section in
                            sectionPanel(section)
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, AtlasSpace.gutter)
                .padding(.top, AtlasSpace.block)
                // Clears the floating Ask Atlas button, which otherwise covers
                // the last lines of a note in a small window.
                .padding(.bottom, 120)
            }
            .background(theme.canvas)
            // Going back lands where you left rather than at the top, which is
            // the whole point of following a link inside a paragraph.
            .task(id: anchorTarget) {
                guard let anchorSection else { return }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(anchorSection, anchor: .top)
                }
            }
        }
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onFavorite) {
                    Label(
                        document.isFavorite ? "Remove Favorite" : "Favorite",
                        systemImage: document.isFavorite ? "star.fill" : "star"
                    )
                }
                Button(action: onEdit) {
                    Label("Edit Note", systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// Changes whenever either the note or the requested anchor does, so the
    /// scroll runs again on a second visit to the same note.
    private var anchorTarget: String { "\(document.id)|\(anchorSection ?? "")" }

    // MARK: - Sections

    private func sectionPanel(_ section: AtlasSection) -> some View {
        AtlasPanel(accent: theme.collectionColor(document.accent)) {
            VStack(alignment: .leading, spacing: AtlasSpace.step) {
                AtlasContentHeading(
                    title: section.title,
                    tint: theme.collectionColor(document.accent)
                )
                RichMarkdownView(
                    source: section.markdown,
                    resolveEmbed: { resolveLink($0).map(AtlasNoteEmbedSource.init) },
                    openEmbed: { embedded in
                        guard let target = resolveLink(embedded.title) else { return }
                        onOpen(target, section.id)
                    }
                )
            }
        }
        .id(section.id)
        // Installed per section so a link knows which part of this note it was
        // followed from — that is what makes coming back land in the right place.
        .environment(\.openURL, OpenURLAction { url in
            guard let title = AtlasNoteLinks.title(from: url) else { return .systemAction }
            guard let target = resolveLink(title) else { return .handled }
            onOpen(target, section.id)
            return .handled
        })
    }

    // MARK: - Chrome

    private func backRow(_ title: String) -> some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .black))
                Text("Back to \(title)")
                    .font(AtlasType.mono(11.5, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            HStack(spacing: 12) {
                AtlasMicroLabel(text: document.category, tint: theme.collectionColor(document.accent))
                Text(document.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            Text(document.title)
                .font(AtlasType.display(40, .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !document.summary.isEmpty {
                Text(document.summary)
                    .font(AtlasType.body(17))
                    .foregroundStyle(theme.textSecondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 700, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// This note's companions, folded away until asked for. The main note is
    /// the way in to everything the lecture produced.
    private var linkedNotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showsLinked.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(showsLinked ? 90 : 0))
                    AtlasMicroLabel(
                        text: children.count == 1 ? "1 linked note" : "\(children.count) linked notes"
                    )
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsLinked {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children) { child in
                        Button { onOpen(child, nil) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: child.isAgentOnly ? "sparkles" : "doc.text")
                                    .font(.system(size: 12))
                                    .foregroundStyle(child.isAgentOnly ? theme.highlight : theme.primary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(child.title)
                                        .font(AtlasType.body(14.5, .semibold))
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    Text(child.isAgentOnly ? "written for the assistant" : child.summary)
                                        .font(AtlasType.mono(10.5))
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        AtlasFadingRule()
                    }
                }
                .padding(.leading, 20)
            }
            AtlasFadingRule()
        }
    }

    private func sectionNavigator(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(sections) { section in
                    AtlasInlineAction(title: section.title, tint: theme.textSecondary) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Document sections")
    }
}
