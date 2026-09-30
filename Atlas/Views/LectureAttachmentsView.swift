import AtlasCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

/// Slides, handouts, and readings attached to one lecture.
///
/// Attached text is treated as the written record: it corrects terms the audio
/// misheard and fills in definitions the lecturer only gestured at. Files are
/// copied into Atlas, so moving the original later does not empty the lecture.
struct LectureAttachmentsView: View {
    let lecture: AtlasLectureSnapshot
    let attachments: [AtlasAttachmentSnapshot]
    let onAdd: ([URL]) -> Void
    let onRemove: (AtlasAttachmentSnapshot) -> Void
    let onRewrite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var isImporting = false

    private static let allowedTypes: [UTType] = [
        .pdf,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "docx") ?? .data,
        .plainText, .rtf, .commaSeparatedText, .json,
        UTType(filenameExtension: "md") ?? .plainText
    ]

    private var readableCount: Int {
        attachments.count(where: \.hasText)
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "paperclip",
            title: "Attached material",
            subtitle: lecture.titleGuess,
            confirmTitle: "Rewrite notes",
            isConfirmEnabled: readableCount > 0,
            secondaryTitle: "Add files…",
            onSecondary: { isImporting = true },
            onCancel: { dismiss() },
            onConfirm: onRewrite
        ) {
            if attachments.isEmpty {
                emptyState
            } else {
                AtlasField(label: "Files", hint: "\(readableCount) of \(attachments.count) readable") {
                    VStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            AttachmentRow(attachment: attachment) { onRemove(attachment) }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                Text("Atlas reads text from PowerPoint, Word, PDF, plain text, Markdown, RTF, CSV, and JSON. PowerPoint keeps its slide numbers, so notes can cite a slide. A scanned PDF has no text to read. Rewriting rebuilds this lecture's notes using the transcript and everything attached.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .atlasSheetFrame(macWidth: 520, minHeight: 440)
        .presentationBackground(.clear)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result { onAdd(urls) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.title2)
                .foregroundStyle(theme.textSecondary)
            Text("Nothing attached yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Add the slides or reading for this lecture and Atlas will use them to sharpen the notes.")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add files…") { isImporting = true }
                .buttonStyle(AtlasCompactPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

private struct AttachmentRow: View {
    let attachment: AtlasAttachmentSnapshot
    let onRemove: () -> Void
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.hasText ? "doc.text.fill" : "doc.fill")
                .font(.system(size: 13))
                .foregroundStyle(attachment.hasText ? theme.primary : theme.warmAccent)
                .frame(width: 28, height: 28)
                .background(
                    (attachment.hasText ? theme.primary : theme.warmAccent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(attachment.hasText ? theme.textSecondary : theme.warmAccent)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove this file")
            .accessibilityLabel("Remove \(attachment.displayName)")
        }
        .padding(9)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.divider, lineWidth: 1)
        }
    }

    private var detail: String {
        if let note = attachment.extractionNote, !attachment.hasText { return note }
        let words = attachment.wordCount == 1 ? "1 word" : "\(attachment.wordCount) words"
        var parts = [attachment.sizeLabel, "\(words) read"]
        // Page counts are what make a citation possible, so show them.
        if let pageLabel = attachment.pageLabel { parts.insert(pageLabel, at: 1) }
        return parts.joined(separator: " · ")
    }
}

#endif
