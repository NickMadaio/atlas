import AtlasCore
import SwiftUI

#if os(macOS)

/// Every lecture Atlas has recorded, and what became of it.
///
/// One expanding row per lecture: the headline says what it is and how it went,
/// and opening it reveals everything you can do with it. Attaching slides is a
/// first-class action there rather than a button competing for space in a row.
struct LecturesView: View {
    @ObservedObject var library: AtlasLibraryStore
    @ObservedObject var capture: LectureCaptureModel
    let openDocument: (AtlasDocumentSnapshot) -> Void
    let reportError: (Error) -> Void
    @Environment(\.atlasPalette) private var theme

    @State private var lectureToDelete: AtlasLectureSnapshot?
    @State private var transcriptToEdit: AtlasLectureSnapshot?
    @State private var attachmentsFor: AtlasLectureSnapshot?
    @State private var expanded: Set<String> = []
    /// Edited per lecture and held until saved, so switching rows does not
    /// silently discard what was typed in another one.
    @State private var contextDrafts: [String: String] = [:]
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lectures")
                        .font(AtlasType.display(30, .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Recorded, transcribed and filed on this Mac")
                        .font(AtlasType.mono(10.5))
                        .foregroundStyle(theme.textSecondary)
                }
                AtlasInlineAction(title: "Import notes", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, AtlasSpace.step)

            if library.lectures.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("No lectures yet.")
                        .font(AtlasType.body(15))
                        .foregroundStyle(theme.textSecondary)
                    Text("Press Record lecture when class starts. Atlas transcribes it here when you end it.")
                        .font(AtlasType.body(13.5))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(library.lectures) { lecture in
                            lectureRow(lecture)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.canvas)
        .sheet(isPresented: $isImporting) {
            ImportNotesView(
                readFile: { capture.readTextForImport(from: $0) },
                onImport: { text, title, hint in
                    capture.importText(text, title: title, courseHint: hint)
                },
                reportError: reportError
            )
        }
        .sheet(item: $attachmentsFor) { lecture in
            LectureAttachmentsView(
                lecture: lecture,
                attachments: library.attachments(for: lecture.id),
                onAdd: { urls in
                    let problems = capture.attachFiles(urls, to: lecture.id)
                    if let first = problems.first { reportError(AttachmentProblem(message: first)) }
                },
                onRemove: { capture.removeAttachment($0) },
                onRewrite: {
                    attachmentsFor = nil
                    capture.process(lectureID: lecture.id)
                }
            )
        }
        .sheet(item: $transcriptToEdit) { lecture in
            LectureTranscriptView(lecture: lecture) { text in
                save(text, for: lecture, rewriting: false)
            } onSaveAndRewrite: { text in
                save(text, for: lecture, rewriting: true)
            }
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(
                get: { lectureToDelete != nil },
                set: { if !$0 { lectureToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Recording and Notes", role: .destructive) {
                if let lectureToDelete {
                    capture.discard(lectureID: lectureToDelete.id, includingNotes: true)
                }
                lectureToDelete = nil
            }
            Button("Delete Recording, Keep Notes") {
                if let lectureToDelete {
                    capture.discard(lectureID: lectureToDelete.id, includingNotes: false)
                }
                lectureToDelete = nil
            }
            Button("Cancel", role: .cancel) { lectureToDelete = nil }
        } message: {
            Text("The audio, transcript and attachments go either way. Keeping the notes leaves them in your folders with no recording behind them.")
        }
    }

    @ViewBuilder
    private func lectureRow(_ lecture: AtlasLectureSnapshot) -> some View {
        let attachments = library.attachments(for: lecture.id)
        let study = lecture.studyDocumentID.flatMap(library.document(id:))
        let depth = lecture.depthDocumentID.flatMap(library.document(id:))

        AtlasExpandingRow(
            title: study?.title ?? lecture.titleGuess,
            caption: caption(for: lecture, attachments: attachments.count),
            accent: tint(for: lecture.stage),
            isExpanded: Binding(
                get: { expanded.contains(lecture.id) },
                set: { open in
                    if open { expanded.insert(lecture.id) } else { expanded.remove(lecture.id) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: AtlasSpace.step) {
                HStack(spacing: 12) {
                    AtlasStateTag(
                        text: lecture.stage.label,
                        tint: tint(for: lecture.stage),
                        showsSpinner: lecture.stage.isWorking
                    )
                    if let collectionTitle = collectionTitle(for: lecture) {
                        Text(collectionTitle)
                            .font(AtlasType.mono(10.5))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                if let failureReason = lecture.failureReason {
                    Text(failureReason)
                        .font(AtlasType.body(13.5))
                        .foregroundStyle(theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Attaching is the action people look for and could not find,
                // so it states what is attached rather than only offering a verb.
                if !lecture.isImported {
                VStack(alignment: .leading, spacing: AtlasSpace.hair) {
                    AtlasMicroLabel(text: "slides & readings", size: 9)
                    if attachments.isEmpty {
                        Text("Nothing attached. Adding the slides lets Atlas correct misheard terms and cite them.")
                            .font(AtlasType.body(12.5))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 6) {
                                Image(systemName: attachment.hasText ? "doc.text" : "doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(attachment.hasText ? theme.primary : theme.warmAccent)
                                Text(attachment.displayName)
                                    .font(AtlasType.body(13.5))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                if let pageLabel = attachment.pageLabel {
                                    Text(pageLabel)
                                        .font(AtlasType.mono(10))
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                        }
                    }
                    AtlasSolidAction(
                        title: attachments.isEmpty ? "Attach slides" : "Manage attachments",
                        systemImage: "paperclip"
                    ) { attachmentsFor = lecture }
                    .padding(.top, 2)
                }
                }

                contextEditor(for: lecture)

                // Two per row, because this pane can be dragged narrow and six
                // actions across one line is how they end up on top of the next
                // lecture.
                VStack(alignment: .leading, spacing: AtlasSpace.tight) {
                    HStack(spacing: AtlasSpace.step) {
                        if let study {
                            AtlasInlineAction(title: "Open notes", systemImage: "doc.text") { openDocument(study) }
                        }
                        if lecture.hasUsableTranscript {
                            AtlasInlineAction(
                                title: lecture.isImported ? "Source text" : "Transcript",
                                systemImage: "text.quote"
                            ) { transcriptToEdit = lecture }
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: AtlasSpace.step) {
                        AtlasInlineAction(
                            title: lecture.stage == .complete ? "Rewrite notes" : "Try again",
                            systemImage: "arrow.clockwise",
                            tint: theme.textSecondary
                        ) { capture.process(lectureID: lecture.id) }
                        .disabled(lecture.stage.isWorking)

                        Menu {
                            ForEach(library.collections) { collection in
                                Button(collection.title) { move(lecture: lecture, to: collection.id) }
                                    .disabled(collection.id == lecture.collectionID)
                            }
                        } label: {
                            Text("Move to folder")
                                .font(AtlasType.mono(11.5, .semibold))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: AtlasSpace.step) {
                        if let depth {
                            AtlasInlineAction(
                                title: "Source file",
                                tint: theme.textSecondary
                            ) { openDocument(depth) }
                        }
                        AtlasInlineAction(title: "Delete", isDestructive: true) {
                            lectureToDelete = lecture
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Telling Atlas what it got wrong, in plain words, then rewriting.
    /// Works the same for an import, where "the recording" is the text.
    ///
    /// This is the direct answer to notes that confidently describe the wrong
    /// thing: the transcript is fine, the model was missing one fact, and the
    /// fact is faster to type than anything else is to fix. It is deliberately
    /// next to Rewrite notes, because the two are one action in practice.
    @ViewBuilder
    private func contextEditor(for lecture: AtlasLectureSnapshot) -> some View {
        let draft = Binding(
            get: { contextDrafts[lecture.id] ?? lecture.contextNote },
            set: { contextDrafts[lecture.id] = $0 }
        )
        let changed = draft.wrappedValue != lecture.contextNote

        VStack(alignment: .leading, spacing: AtlasSpace.hair) {
            AtlasMicroLabel(text: "tell atlas about this lecture", size: 9)
            Text(lecture.isImported
                 ? "Anything the text does not say, or anything the notes got wrong. Atlas treats this as fact and rewrites from it."
                 : "Anything the recording could not say, or anything the notes got wrong. Atlas treats this as fact and rewrites from it.")
                .font(AtlasType.body(12.5))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: draft)
                .font(AtlasType.body(13.5))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 74)
                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                }

            HStack(spacing: AtlasSpace.step) {
                AtlasSolidAction(title: "Save and rewrite notes", systemImage: "arrow.clockwise") {
                    if saveContext(draft.wrappedValue, for: lecture) {
                        capture.process(lectureID: lecture.id)
                    }
                }
                .disabled(lecture.stage.isWorking)

                if changed {
                    AtlasInlineAction(title: "Save only", tint: theme.textSecondary) {
                        _ = saveContext(draft.wrappedValue, for: lecture)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @discardableResult
    private func saveContext(_ note: String, for lecture: AtlasLectureSnapshot) -> Bool {
        do {
            try capture.setContext(note, for: lecture.id)
            contextDrafts.removeValue(forKey: lecture.id)
            return true
        } catch {
            reportError(error)
            return false
        }
    }

    private func caption(for lecture: AtlasLectureSnapshot, attachments: Int) -> String {
        var parts = [
            lecture.startedAt.formatted(date: .abbreviated, time: .shortened),
            lecture.durationLabel
        ]
        if attachments > 0 { parts.append("\(attachments) attached") }
        if lecture.hasContextNote { parts.append("has context") }
        if let model = lecture.modelIdentifier { parts.append(model) }
        else if lecture.stage == .completeWithoutModel { parts.append("transcript only") }
        return parts.joined(separator: " · ")
    }

    private func tint(for stage: AtlasLectureStage) -> Color {
        switch stage {
        case .complete: theme.primary
        case .completeWithoutModel: theme.warmAccent
        case .failed: theme.danger
        default: theme.highlight
        }
    }

    private func collectionTitle(for lecture: AtlasLectureSnapshot) -> String? {
        lecture.collectionID.flatMap { id in
            library.collectionPath(for: id).map(\.title).joined(separator: " › ")
        }
    }

    private func save(_ text: String, for lecture: AtlasLectureSnapshot, rewriting: Bool) {
        do {
            try library.updateTranscript(lectureID: lecture.id, text: text)
            transcriptToEdit = nil
            if rewriting { capture.process(lectureID: lecture.id) }
        } catch { reportError(error) }
    }

    private func move(lecture: AtlasLectureSnapshot, to collectionID: String) {
        do { try library.moveLecture(id: lecture.id, toCollection: collectionID) }
        catch { reportError(error) }
    }
}

/// Surfaces a file that could not be attached, using the app's usual error path.
private struct AttachmentProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

#endif
