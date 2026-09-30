import AtlasCore
import SwiftUI

#if os(macOS)
import UniformTypeIdentifiers

/// Turning text you already have into Atlas notes.
///
/// A lecture is not the only thing worth having structured notes for — a
/// reading, a page from Canvas, someone else's notes, a transcript from
/// somewhere that is not this app. All of that is text, and everything Atlas
/// does after transcription is about text, so it runs the same pipeline and
/// comes out the same shape.
struct ImportNotesView: View {
    let readFile: (URL) -> Result<String, Error>
    let onImport: (String, String, String?) -> Void
    let reportError: (Error) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var text = ""
    @State private var title = ""
    @State private var courseHint = ""
    @State private var sourceName: String?
    @State private var isImporting = false

    private var canImport: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AtlasSpace.block) {
                header
                sourceSection
                detailsSection
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, AtlasSpace.gutter)
            .padding(.vertical, AtlasSpace.block)
        }
        .frame(minWidth: 720, minHeight: 640)
        .background(theme.canvas)
        .presentationBackground(theme.canvas)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ImportNotesView.acceptedTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            switch readFile(url) {
            case let .success(extracted):
                text = extracted
                sourceName = url.lastPathComponent
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
            case let .failure(error):
                reportError(error)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Write notes") {
                    onImport(
                        text,
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        courseHint.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    )
                    dismiss()
                }
                .disabled(!canImport)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    static let acceptedTypes: [UTType] = [
        .pdf, .plainText, .rtf, .rtfd, .utf8PlainText,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "vtt") ?? .plainText,
        UTType(filenameExtension: "srt") ?? .plainText
    ]

    private var header: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.hair) {
            AtlasMicroLabel(text: "import", size: 9.5)
            Text("Turn anything into Atlas notes")
                .font(AtlasType.display(25, .bold))
                .foregroundStyle(theme.textPrimary)
            Text("A reading, a transcript from somewhere else, a page you copied, notes a friend took. Atlas structures it exactly the way it structures a lecture — outline, terms, a quiz — and files it into a class.")
                .font(AtlasType.body(14.5))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            AtlasSectionRule(
                title: "the text",
                trailing: canImport ? "\(text.count) characters" : nil
            )

            TextEditor(text: $text)
                .font(AtlasType.body(14))
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(minHeight: 240)
                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste here, or choose a file.")
                            .font(AtlasType.body(14))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 22)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: AtlasSpace.step) {
                AtlasInlineAction(title: "Choose a file", systemImage: "doc.badge.plus") {
                    isImporting = true
                }
                if let sourceName {
                    Text(sourceName)
                        .font(AtlasType.mono(10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text("PDF, Word, PowerPoint, Markdown, plain text, or a .vtt/.srt caption file.")
                .font(AtlasType.mono(10))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.tight) {
            AtlasSectionRule(title: "where it belongs")

            AtlasFieldRow(label: "Title", placeholder: "Left blank, Atlas writes one", text: $title)
            AtlasFieldRow(label: "Class", placeholder: "Optional — e.g. CS 2100", text: $courseHint)

            Text("Atlas picks the folder itself, using the class if you give one. You can move it afterwards.")
                .font(AtlasType.mono(10))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A labelled single-line field, matching the rest of the app's inputs.
struct AtlasFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AtlasMicroLabel(text: label, size: 9)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AtlasType.body(14.5))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                }
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#endif
