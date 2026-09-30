#if os(macOS)
import AtlasCore
import SwiftUI

/// Files the current sketch: as a note of its own, or into a lecture's notes.
struct SketchSaveSheet: View {
    enum Destination: String, CaseIterable, Identifiable {
        case newNote = "New note"
        case lecture = "Add to lecture"
        var id: String { rawValue }
    }

    @ObservedObject var library: AtlasLibraryStore
    @ObservedObject var sketch: TrackpadSketchModel
    let onFiled: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme

    @State private var destination: Destination = .newNote
    @State private var title = ""
    @State private var folderID: String?
    @State private var lectureID: String?
    @State private var startsFreshPage = true
    @State private var problem: String?

    private var folders: [AtlasCollectionNode] { library.collectionTree().flatMap(\.flattened) }

    /// Only lectures that have finished notes can take a sketch.
    private var lectures: [(lecture: AtlasLectureSnapshot, note: AtlasDocumentSnapshot)] {
        library.lectures
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { lecture in
                lecture.studyDocumentID.flatMap(library.document(id:)).map { (lecture, $0) }
            }
    }

    private var canSave: Bool {
        switch destination {
        case .newNote: !title.trimmingCharacters(in: .whitespaces).isEmpty && folderID != nil
        case .lecture: lectureID != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save sketch")
                .font(AtlasType.display(20, .bold))
                .foregroundStyle(theme.textPrimary)

            Picker("", selection: $destination) {
                ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(destination == .newNote ? "Note title" : "Caption (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            switch destination {
            case .newNote: folderPicker
            case .lecture: lecturePicker
            }

            Toggle("Start a fresh page after saving", isOn: $startsFreshPage)
                .font(AtlasType.body(13))

            if let problem {
                Text(problem)
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(AtlasQuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(AtlasCompactPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            folderID = folderID ?? folders.first?.id
            lectureID = lectureID ?? lectures.first?.lecture.id
        }
    }

    private var folderPicker: some View {
        Picker("Folder", selection: $folderID) {
            ForEach(folders, id: \.id) { node in
                Text(String(repeating: "   ", count: node.depth) + node.collection.title)
                    .tag(Optional(node.id))
            }
        }
        .disabled(folders.isEmpty)
    }

    @ViewBuilder
    private var lecturePicker: some View {
        if lectures.isEmpty {
            Text("No lecture has finished notes yet.")
                .font(AtlasType.mono(10.5))
                .foregroundStyle(theme.textSecondary)
        } else {
            Picker("Lecture", selection: $lectureID) {
                ForEach(lectures, id: \.lecture.id) { entry in
                    Text("\(entry.note.title) — \(entry.lecture.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        .tag(Optional(entry.lecture.id))
                }
            }
        }
    }

    /// The sketch file is written before any note refers to it, so a note can
    /// never point at a sketch that is not on disk.
    private func save() {
        do {
            let id = try sketch.saveSnapshot(to: SketchFiles.directory)
            let filedTitle = try file(id)
            if startsFreshPage { sketch.startFreshPage() }
            onFiled(filedTitle)
            dismiss()
        } catch {
            problem = "Could not save: \(error.localizedDescription)"
        }
    }

    private func file(_ id: UUID) throws -> String {
        switch destination {
        case .newNote:
            guard let folderID else { throw AtlasSimpleError(message: "Choose a folder.") }
            let cleanTitle = title.trimmingCharacters(in: .whitespaces)
            _ = try library.createDocument(
                in: folderID,
                title: cleanTitle,
                category: "Sketch",
                bodyMarkdown: SketchEmbed.appending(id, caption: "", to: "")
            )
            return cleanTitle
        case .lecture:
            guard let entry = lectures.first(where: { $0.lecture.id == lectureID }) else {
                throw AtlasSimpleError(message: "Choose a lecture.")
            }
            let note = entry.note
            try library.updateDocument(
                id: note.id,
                title: note.title,
                summary: note.summary,
                category: note.category,
                bodyMarkdown: SketchEmbed.appending(id, caption: title, to: note.bodyMarkdown)
            )
            return note.title
        }
    }
}
#endif
