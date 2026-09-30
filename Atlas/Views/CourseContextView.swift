import AtlasCore
import SwiftUI

#if os(macOS)
import UniformTypeIdentifiers

/*
 What Atlas knows about a class before it writes a word.

 This is the fix for notes that confidently describe the wrong thing. A model
 reading an automatic transcript has no idea what the course is: a passing
 mention of another language, in an hour about this one, looks exactly like the
 subject. Told once, in plain words, that the course is taught in Python, it
 reads the same transcript correctly.

 Two ways in, because they fail differently. Typed context is short, exact and
 always applies. Attached material — the syllabus, the module outline — is long
 and authoritative but only covers what someone wrote down.
*/
struct CourseContextView: View {
    let collection: AtlasCollectionSnapshot
    let path: String
    let inheritedFrom: [(title: String, briefing: String)]
    let material: [AtlasAttachmentSnapshot]
    let initialBriefing: String
    let onSave: (String) -> Void
    let onAddMaterial: ([URL]) -> Void
    let onRemoveMaterial: (AtlasAttachmentSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var briefing = ""
    @State private var isImporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AtlasSpace.block) {
                header
                briefingEditor
                if !inheritedFrom.isEmpty { inherited }
                materialSection
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, AtlasSpace.gutter)
            .padding(.vertical, AtlasSpace.block)
        }
        .frame(minWidth: 700, minHeight: 620)
        .background(theme.canvas)
        .presentationBackground(theme.canvas)
        .onAppear { briefing = initialBriefing }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: CourseContextView.acceptedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result { onAddMaterial(urls) }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(briefing)
                    dismiss()
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    static let acceptedTypes: [UTType] = [
        .pdf, .plainText, .rtf,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "md") ?? .plainText
    ]

    private var header: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.hair) {
            AtlasMicroLabel(text: path, size: 9.5)
            Text("What should Atlas know about this class?")
                .font(AtlasType.display(25, .bold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Written once, used on every lecture in this folder. It outranks the transcript — when the audio seems to say something that contradicts this, Atlas treats the audio as misheard.")
                .font(AtlasType.body(14.5))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var briefingEditor: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            AtlasSectionRule(title: "what atlas should know")
            TextEditor(text: $briefing)
                .font(AtlasType.body(14.5))
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(minHeight: 180)
                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if briefing.isEmpty {
                        Text(CourseContextView.placeholder)
                            .font(AtlasType.body(14.5))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text("\(briefing.count) / \(AtlasLibraryStore.maximumCourseBriefingCharacters)")
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
                Text("After saving, use Rewrite notes on a lecture to apply this to notes you already have.")
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    static let placeholder = """
    Everything is taught in Python 3 — never Java or C.
    We use pytest, and plain assert statements rather than a test framework's own.
    The lecturer is Dr Mohanan; labs are separate from lectures.
    Slides live on Canvas under Pages, one per week.
    """

    /// Context set on a parent folder applies here too, so it is shown rather
    /// than silently in force.
    private var inherited: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            AtlasSectionRule(title: "inherited from folders above")
            ForEach(inheritedFrom, id: \.title) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    AtlasMicroLabel(text: entry.title, size: 9)
                    Text(entry.briefing)
                        .font(AtlasType.body(13.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("These apply to every class in that folder, including this one.")
                .font(AtlasType.mono(10))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            AtlasSectionRule(title: "course material", trailing: material.isEmpty ? nil : "\(material.count)")
            Text("A syllabus or module outline, read once and used on every lecture in this class. PDF, Word, PowerPoint, or plain text.")
                .font(AtlasType.body(13.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(material) { file in
                HStack(spacing: 10) {
                    Image(systemName: file.hasText ? "doc.text" : "doc")
                        .font(.system(size: 12))
                        .foregroundStyle(file.hasText ? theme.primary : theme.warmAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.displayName)
                            .font(AtlasType.body(14))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(file.hasText
                             ? [file.pageLabel, "\(file.wordCount) words", file.sizeLabel].compactMap { $0 }.joined(separator: " \u{00B7} ")
                             : (file.extractionNote ?? "No readable text in this file."))
                            .font(AtlasType.mono(10))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    AtlasInlineAction(title: "Remove", isDestructive: true) { onRemoveMaterial(file) }
                }
                .padding(.vertical, 8)
                AtlasFadingRule()
            }

            AtlasSolidAction(title: "Add course material", systemImage: "paperclip") {
                isImporting = true
            }
            .padding(.top, AtlasSpace.hair)
        }
    }
}

#endif
