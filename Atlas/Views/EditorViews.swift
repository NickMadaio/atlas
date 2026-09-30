import AtlasCore
import SwiftUI

/// One choice in a "which folder?" menu, already indented for its depth.
struct CollectionChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let depth: Int
    var isSelectable: Bool = true

    var indentedTitle: String {
        String(repeating: "    ", count: depth) + title
    }
}

/// A folder picker.
///
/// Uses a real popup button rather than a styled `Menu`: a borderless menu
/// drops its custom background, which left the control reading as plain text
/// with no affordance at all. Folders that would create a cycle are left out
/// of the list entirely instead of being shown greyed — you cannot pick what
/// is not offered.
struct CollectionPicker: View {
    let label: String
    let hint: String?
    let choices: [CollectionChoice]
    let allowsTopLevel: Bool
    @Binding var selection: String?
    @Environment(\.atlasPalette) private var theme

    private var selectable: [CollectionChoice] {
        choices.filter(\.isSelectable)
    }

    var body: some View {
        AtlasField(label: label, hint: hint) {
            HStack(spacing: 8) {
                Image(systemName: selection == nil ? "tray.full.fill" : "folder.fill")
                    .font(.caption)
                    .foregroundStyle(theme.primary)
                Picker("", selection: $selection) {
                    if allowsTopLevel {
                        Text("Top level").tag(String?.none)
                    }
                    ForEach(selectable) { choice in
                        Text(choice.indentedTitle).tag(String?.some(choice.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(label)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.divider, lineWidth: 1)
            }
        }
    }
}

struct NewDocumentView: View {
    let collectionTitle: String
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var category = "Notes"
    @FocusState private var titleFocused: Bool

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "square.and.pencil",
            title: "New note",
            subtitle: "In \(collectionTitle)",
            confirmTitle: "Create note",
            isConfirmEnabled: isValid,
            onCancel: { dismiss() },
            onConfirm: { if isValid { onSave(title, summary, category) } }
        ) {
            AtlasField(label: "Title") {
                TextField("What is this note about?", text: $title)
                    .atlasInput()
                    .focused($titleFocused)
                    .accessibilityLabel("Note title")
            }
            AtlasField(label: "Short description", hint: "optional") {
                TextField("One line you will recognise later", text: $summary, axis: .vertical)
                    .atlasInput(minHeight: 58)
                    .lineLimit(2...4)
            }
            AtlasField(label: "Category", hint: "shown as the tag on the note") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Notes", text: $category)
                        .atlasInput()
                    AtlasSuggestionChips(
                        options: ["Notes", "Lecture", "Reading", "Assignment", "Reference", "Idea"],
                        selection: $category
                    )
                }
            }
        }
        .atlasSheetFrame(macWidth: 470, minHeight: 424)
        .presentationBackground(.clear)
        .onAppear { titleFocused = true }
    }
}

struct NewCollectionView: View {
    let choices: [CollectionChoice]
    let onSave: (String, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var parentID: String?
    @FocusState private var titleFocused: Bool

    init(
        choices: [CollectionChoice],
        initialParentID: String? = nil,
        onSave: @escaping (String, String, String?) -> Void
    ) {
        self.choices = choices
        self.onSave = onSave
        _parentID = State(initialValue: initialParentID)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "folder.badge.plus",
            title: "New folder",
            subtitle: "Folders can hold notes, other folders, or both.",
            confirmTitle: "Create folder",
            isConfirmEnabled: isValid,
            onCancel: { dismiss() },
            onConfirm: { if isValid { onSave(title, summary, parentID) } }
        ) {
            AtlasField(label: "Name") {
                TextField("DS 1800, Week 3, Readings…", text: $title)
                    .atlasInput()
                    .focused($titleFocused)
                    .accessibilityLabel("Folder name")
            }
            AtlasField(label: "What belongs here?", hint: "optional") {
                TextField("A line to remind you what this is for", text: $summary, axis: .vertical)
                    .atlasInput(minHeight: 58)
                    .lineLimit(2...4)
            }
            CollectionPicker(
                label: "Inside",
                hint: "leave at top level to keep it alongside the others",
                choices: choices,
                allowsTopLevel: true,
                selection: $parentID
            )
        }
        .atlasSheetFrame(macWidth: 470, minHeight: 376)
        .presentationBackground(.clear)
        .onAppear { titleFocused = true }
    }
}

/// Rename a folder, move it somewhere else, or delete it.
struct CollectionEditorView: View {
    let collection: AtlasCollectionSnapshot
    let choices: [CollectionChoice]
    let contentsDescription: String
    let canDelete: Bool
    let onSave: (String, String, String?) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var title: String
    @State private var summary: String
    @State private var parentID: String?

    init(
        collection: AtlasCollectionSnapshot,
        choices: [CollectionChoice],
        contentsDescription: String,
        canDelete: Bool,
        onSave: @escaping (String, String, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.collection = collection
        self.choices = choices
        self.contentsDescription = contentsDescription
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: collection.title)
        _summary = State(initialValue: collection.summary)
        _parentID = State(initialValue: collection.parentID)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "folder.fill",
            title: "Folder settings",
            subtitle: contentsDescription,
            confirmTitle: "Save",
            isConfirmEnabled: isValid,
            onCancel: { dismiss() },
            onConfirm: { if isValid { onSave(title, summary, parentID) } }
        ) {
            AtlasField(label: "Name") {
                TextField("Folder name", text: $title)
                    .atlasInput()
            }
            AtlasField(label: "What belongs here?", hint: "optional") {
                TextField("A line to remind you what this is for", text: $summary, axis: .vertical)
                    .atlasInput(minHeight: 58)
                    .lineLimit(2...4)
            }
            CollectionPicker(
                label: "Inside",
                hint: "this folder and its contents are not listed",
                choices: choices,
                allowsTopLevel: true,
                selection: $parentID
            )

            VStack(alignment: .leading, spacing: 7) {
                Divider().padding(.vertical, 2)
                Button("Delete folder", role: .destructive, action: onDelete)
                    .buttonStyle(AtlasDestructiveButtonStyle())
                    .disabled(!canDelete)
                    .opacity(canDelete ? 1 : 0.45)
                Text(canDelete
                    ? "This folder is empty, so deleting it removes nothing else."
                    : "Move or delete what is inside this folder first.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .atlasSheetFrame(macWidth: 470, minHeight: 500)
        .presentationBackground(.clear)
    }
}

struct DocumentEditorView: View {
    let document: AtlasDocumentSnapshot
    let onSave: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    @State private var title: String
    @State private var summary: String
    @State private var category: String
    @State private var bodyMarkdown: String

    init(
        document: AtlasDocumentSnapshot,
        onSave: @escaping (String, String, String, String) -> Void
    ) {
        self.document = document
        self.onSave = onSave
        _title = State(initialValue: document.title)
        _summary = State(initialValue: document.summary)
        _category = State(initialValue: document.category)
        _bodyMarkdown = State(initialValue: document.bodyMarkdown)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AtlasSheetShell(
            symbol: "pencil.and.outline",
            title: "Edit note",
            subtitle: document.title,
            confirmTitle: "Save changes",
            isConfirmEnabled: isValid,
            onCancel: { dismiss() },
            onConfirm: { if isValid { onSave(title, summary, category, bodyMarkdown) } }
        ) {
            AtlasField(label: "Title") {
                TextField("Note title", text: $title)
                    .atlasInput()
            }
            HStack(alignment: .top, spacing: 12) {
                AtlasField(label: "Short description", hint: "optional") {
                    TextField("One line summary", text: $summary, axis: .vertical)
                        .atlasInput(minHeight: 58)
                        .lineLimit(2...3)
                }
                AtlasField(label: "Category") {
                    TextField("Notes", text: $category)
                        .atlasInput()
                        .frame(width: 150)
                }
            }
            AtlasField(label: "Markdown", hint: "## starts a new navigable section") {
                TextEditor(text: $bodyMarkdown)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 280)
                    .padding(8)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.divider, lineWidth: 1)
                    }
                    .accessibilityLabel("Note Markdown")
            }
        }
        .atlasSheetFrame(macWidth: 700, minHeight: 640)
        .presentationBackground(.clear)
    }
}
