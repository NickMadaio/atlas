import AtlasCore
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var library: AtlasLibraryStore
    @ObservedObject var auth: AuthSessionStore
    let environment: BackendConfiguration
    let showSettings: () -> Void
    let reportError: (Error) -> Void
    @Environment(\.atlasPalette) private var theme
#if os(macOS)
    @EnvironmentObject private var lectureCapture: LectureCaptureModel
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var isShowingLectures = false
    @State private var selectedCollectionID: String?
    @State private var selectedDocumentID: String?
    @State private var searchText = ""
    @State private var isPresentingNewDocument = false
    @State private var isPresentingNewCollection = false
    @State private var isPresentingContextAssistant = false
    @State private var documentToEdit: AtlasDocumentSnapshot?
    @State private var documentToDelete: AtlasDocumentSnapshot?
    @State private var collectionToEdit: AtlasCollectionSnapshot?
    @State private var newCollectionParentID: String?
    @State private var collectionForContext: AtlasCollectionSnapshot?
    /// Where you came from, and the part of it you were reading. Following a
    /// link inside a paragraph has to be undoable, or a linked note is a trap.
    @State private var history: [NoteVisit] = []
    @State private var anchorSection: String?
    @AppStorage("atlas.sidebar.expandedCollections") private var expandedStorage = ""

    /// One step of reading history.
    struct NoteVisit: Equatable {
        let documentID: String
        let sectionID: String?
    }

    private var selectedCollection: AtlasCollectionSnapshot? {
        library.collections.first(where: { $0.id == selectedCollectionID })
    }

    private var visibleDocuments: [AtlasDocumentSnapshot] {
        guard let selectedCollectionID else { return [] }
        return library.documents(in: selectedCollectionID, matching: searchText)
    }

    private var selectedDocument: AtlasDocumentSnapshot? {
        selectedDocumentID.flatMap(library.document(id:))
    }

    private var assistantContext: AtlasLocalContext {
        let scopedDocuments: [AtlasDocumentSnapshot]
        if let selectedDocument {
            scopedDocuments = [selectedDocument]
        } else if let selectedCollection {
            scopedDocuments = library.documents(in: selectedCollection.id, includingAgentOnly: true)
        } else {
            scopedDocuments = library.documents
        }
        return AtlasLocalContext(
            collection: selectedCollection,
            document: selectedDocument,
            documents: scopedDocuments
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            documentList
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottomTrailing) {
            Button {
                isPresentingContextAssistant = true
            } label: {
                Label("Ask Atlas", systemImage: "sparkles")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(theme.heroGradient, in: Capsule())
                    .contentShape(Capsule())
                    .shadow(color: theme.primaryStrong.opacity(0.24), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .padding(18)
            .accessibilityHint("Opens local help for the collection or note currently displayed")
        }
        .onAppear {
            repairSelection()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--atlas-open-assistant") {
                isPresentingContextAssistant = true
            }
            #endif
        }
        .onChange(of: library.collections) { _, _ in repairSelection() }
        .onChange(of: library.documents) { _, _ in repairSelection() }
        .sheet(isPresented: $isPresentingNewDocument) {
            if let selectedCollectionID {
                NewDocumentView(collectionTitle: selectedCollection?.title ?? "this folder") { title, summary, category in
                    do {
                        selectedDocumentID = try library.createDocument(
                            in: selectedCollectionID,
                            title: title,
                            summary: summary,
                            category: category
                        )
                        isPresentingNewDocument = false
                    } catch { reportError(error) }
                }
            }
        }
        .sheet(isPresented: $isPresentingNewCollection) {
            NewCollectionView(
                choices: collectionChoices(),
                initialParentID: newCollectionParentID
            ) { title, summary, parentID in
                do {
                    let created = try library.createCollection(title: title, summary: summary, parentID: parentID)
                    if let parentID { expand(parentID) }
                    isShowingLectures = false
                    selectedCollectionID = created
                    selectedDocumentID = nil
                    isPresentingNewCollection = false
                } catch { reportError(error) }
            }
        }
        .sheet(item: $collectionToEdit) { collection in
            CollectionEditorView(
                collection: collection,
                choices: collectionChoices(excluding: collection.id),
                contentsDescription: contentsDescription(for: collection),
                canDelete: isEmptyCollection(collection)
            ) { title, summary, parentID in
                do {
                    try library.renameCollection(id: collection.id, title: title, summary: summary)
                    if parentID != collection.parentID {
                        try library.moveCollection(id: collection.id, toParent: parentID)
                        if let parentID { expand(parentID) }
                    }
                    collectionToEdit = nil
                } catch { reportError(error) }
            } onDelete: {
                do {
                    try library.deleteCollection(id: collection.id)
                    if selectedCollectionID == collection.id {
                        selectedCollectionID = nil
                        selectedDocumentID = nil
                    }
                    collectionToEdit = nil
                } catch { reportError(error) }
            }
        }
        .sheet(item: $documentToEdit) { document in
            DocumentEditorView(document: document) { title, summary, category, body in
                do {
                    try library.updateDocument(
                        id: document.id,
                        title: title,
                        summary: summary,
                        category: category,
                        bodyMarkdown: body
                    )
                    documentToEdit = nil
                } catch { reportError(error) }
            }
        }
        .sheet(isPresented: $isPresentingContextAssistant) {
            ContextAssistantView(context: assistantContext)
                .id(assistantContext.id)
        }
#if os(macOS)
        .sheet(item: $collectionForContext) { collection in
            CourseContextView(
                collection: collection,
                path: library.collectionPath(for: collection.id).map(\.title).joined(separator: " \u{203A} "),
                inheritedFrom: inheritedContext(for: collection),
                material: library.courseAttachments(for: collection.id),
                initialBriefing: library.courseContext(for: collection.id)?.briefing ?? "",
                onSave: { briefing in
                    do { try library.setCourseContext(collectionID: collection.id, briefing: briefing) }
                    catch { reportError(error) }
                },
                onAddMaterial: { urls in
                    let problems = lectureCapture.attachCourseFiles(urls, to: collection.id)
                    if let first = problems.first { reportError(AtlasSimpleError(message: first)) }
                },
                onRemoveMaterial: { file in
                    try? FileManager.default.removeItem(at: lectureCapture.attachmentURL(for: file))
                    do { try library.deleteAttachment(id: file.id) }
                    catch { reportError(error) }
                }
            )
        }
#endif
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { documentToDelete != nil },
                set: { if !$0 { documentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                guard let documentToDelete else { return }
                do {
                    try library.deleteDocument(id: documentToDelete.id)
                    self.documentToDelete = nil
                } catch { reportError(error) }
            }
            Button("Cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("This removes “\(documentToDelete?.title ?? "this note")” from this device. This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                AtlasLogo(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atlas")
                        .font(AtlasType.display(20, .bold))
                        .foregroundStyle(theme.textPrimary)
                    AtlasMicroLabel(text: "your knowledge space", size: 8.5)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    placeRow(
                        title: "Home",
                        detail: "overview and recent",
                        symbol: "square.grid.2x2",
                        isSelected: selectedCollectionID == nil && !isShowingLectures
                    ) {
                        isShowingLectures = false
                        selectedCollectionID = nil
                        selectedDocumentID = nil
                    }

#if os(macOS)
                    placeRow(
                        title: "Lectures",
                        detail: lectureSubtitle,
                        symbol: "waveform",
                        isSelected: isShowingLectures,
                        action: showLectures
                    )

                    placeRow(
                        title: "Sketch Pad",
                        detail: "write with the trackpad",
                        symbol: "hand.draw",
                        isSelected: false
                    ) {
                        openWindow(id: AtlasApp.sketchWindowID)
                    }
#endif

                    HStack(spacing: 10) {
                        AtlasMicroLabel(text: "folders").fixedSize()
                        AtlasFadingRule()
                        Button {
                            newCollectionParentID = nil
                            isPresentingNewCollection = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Folder")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 6)

                    CollectionTreeRows(
                        nodes: library.collectionTree(),
                        parentID: nil,
                        selectedID: selectedCollectionID,
                        expanded: expandedCollections,
                        directCount: { library.noteCount(in: $0, includingSubcollections: false) },
                        totalCount: { library.noteCount(in: $0, includingSubcollections: true) },
                        onSelect: { selectCollection($0.id) },
                        onToggle: toggleExpanded,
                        onAddChild: { collection in
                            newCollectionParentID = collection.id
                            isPresentingNewCollection = true
                        },
                        onEdit: { collectionToEdit = $0 },
                        onDrop: applyDrop
                    )
                    .padding(.horizontal, 10)

                    if library.collections.isEmpty {
                        Text("No folders yet. Use + to make one.")
                            .font(AtlasType.mono(9.5))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    } else {
                        Text("Drag a folder onto another to nest it, or between two to reorder.")
                            .font(AtlasType.mono(8.5))
                            .foregroundStyle(theme.textSecondary.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 14)
            }
            .scrollContentBackground(.hidden)

#if os(macOS)
            LectureRecordBar(capture: lectureCapture, onShowLectures: showLectures)
#endif

            accountFooter
        }
        .background(theme.sidebar)
        .navigationSplitViewColumnWidth(min: 272, ideal: 300, max: 360)
    }

    /// Home and Lectures. Not a folder, so it does not get the folder tree's
    /// nesting affordances.
    private func placeRow(
        title: String,
        detail: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.primary : theme.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AtlasType.body(14.5, isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textPrimary.opacity(0.82))
                    Text(detail)
                        .font(AtlasType.mono(10))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(alignment: .leading) {
                if isSelected {
                    LinearGradient(
                        colors: [theme.primary.opacity(0.20), theme.primary.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var accountFooter: some View {
        HStack(spacing: 9) {
            Circle()
                .stroke(theme.divider, lineWidth: 1)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "person")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(accountTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                Text(environment.baseURL == nil ? "on this device" : "connected")
                    .font(AtlasType.mono(8.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Button { auth.signOut() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign Out")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { AtlasFadingRule() }
    }

    private var accountTitle: String {
        switch auth.state {
        case .signedOut: "Signed out"
        case .guest: "Offline workspace"
        case let .signedIn(account): account.displayName ?? account.email ?? "Atlas account"
        }
    }

    // MARK: - Note list

    private var documentList: some View {
        Group {
            if isShowingLectures {
                lecturesPane
            } else if let selectedCollection {
                collectionPane(selectedCollection)
            } else {
                homeIndexView
            }
        }
        .background(theme.canvas)
        .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
    }

    private func collectionPane(_ collection: AtlasCollectionSnapshot) -> some View {
        let subfolders = library.childCollections(of: collection.id)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                let trail = library.collectionPath(for: collection.id).dropLast()
                if !trail.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(trail.enumerated()), id: \.element.id) { index, ancestor in
                            if index > 0 {
                                Text("\u{203A}")
                                    .font(AtlasType.mono(9, .bold))
                                    .foregroundStyle(theme.textSecondary.opacity(0.5))
                            }
                            Button(ancestor.title) { selectCollection(ancestor.id) }
                                .buttonStyle(.plain)
                                .font(AtlasType.mono(9.5, .semibold))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                Text(collection.title)
                    .font(AtlasType.display(30, .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerCountLabel(for: collection))
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: AtlasSpace.step) {
                    AtlasInlineAction(title: "New note", systemImage: "square.and.pencil") {
                        isPresentingNewDocument = true
                    }
#if os(macOS)
                    AtlasInlineAction(
                        title: hasContext(collection) ? "Class context \u{00B7} set" : "Class context",
                        systemImage: "text.book.closed",
                        tint: hasContext(collection) ? theme.primary : theme.textSecondary
                    ) { collectionForContext = collection }
#endif
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textSecondary)
                    TextField("Search notes", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AtlasType.body(14))
                        .foregroundStyle(theme.textPrimary)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 7)
                .overlay(alignment: .bottom) { AtlasFadingRule() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, AtlasSpace.step)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !subfolders.isEmpty, searchText.isEmpty {
                        AtlasSectionRule(title: "folders inside", trailing: "\(subfolders.count)")
                            .padding(.bottom, 4)
                        ForEach(subfolders) { child in
                            Button { selectCollection(child.id) } label: {
                                FolderRow(
                                    collection: child,
                                    noteCount: library.noteCount(in: child.id, includingSubcollections: true),
                                    childCount: library.childCollections(of: child.id).count
                                )
                            }
                            .buttonStyle(.plain)
                            AtlasFadingRule()
                        }
                        AtlasSectionRule(title: "notes", trailing: "\(visibleDocuments.count)")
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                    }

                    if visibleDocuments.isEmpty {
                        emptyNotes(hasFolders: !subfolders.isEmpty)
                    } else {
                        ForEach(visibleDocuments) { document in
                            Button { selectedDocumentID = document.id } label: {
                                DocumentRow(document: document, isSelected: selectedDocumentID == document.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit") { documentToEdit = document }
                                Button(document.isFavorite ? "Remove Favorite" : "Favorite") {
                                    do { try library.toggleFavorite(id: document.id) }
                                    catch { reportError(error) }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { documentToDelete = document }
                            }
                            AtlasFadingRule()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func emptyNotes(hasFolders: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(searchText.isEmpty
                 ? (hasFolders ? "No notes directly in this folder." : "Nothing here yet.")
                 : "No matches.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
            if searchText.isEmpty {
                AtlasInlineAction(title: "Write the first note", systemImage: "plus") {
                    isPresentingNewDocument = true
                }
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let selectedDocument {
                DocumentDetailView(
                    document: selectedDocument,
                    children: library.childDocuments(of: selectedDocument.id),
                    backTitle: history.last.flatMap { library.document(id: $0.documentID)?.title },
                    anchorSection: anchorSection,
                    onBack: goBack,
                    onEdit: { documentToEdit = selectedDocument },
                    onFavorite: {
                        do { try library.toggleFavorite(id: selectedDocument.id) }
                        catch { reportError(error) }
                    },
                    onOpen: { target, from in follow(to: target, leaving: from) },
                    resolveLink: { library.document(titled: $0) }
                )
            } else if isShowingLectures {
                placeholder(
                    title: "Your lectures",
                    detail: "Open a lecture's notes, correct its transcript, or attach the slides."
                )
            } else if selectedCollectionID == nil {
                homeView
            } else {
                placeholder(title: "Choose a note", detail: "Pick one on the left to read it here.")
            }
        }
    }

    private func placeholder(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            AtlasMicroLabel(text: "atlas")
            Text(title)
                .font(AtlasType.display(32, .bold))
                .foregroundStyle(theme.textPrimary)
            Text(detail)
                .font(AtlasType.body(15))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(40)
        .background(theme.canvas)
    }

    // MARK: - Home

    private var homeView: some View {
        ScrollView {
            // Offset, not grid: the figures sit narrow on the left, the folder
            // list runs wide beneath at a different rhythm.
            VStack(alignment: .leading, spacing: AtlasSpace.block + 8) {
                VStack(alignment: .leading, spacing: 10) {
                    AtlasMicroLabel(text: "your atlas")
                    Text("Everything from class,\nin one place.")
                        .font(AtlasType.display(42, .bold))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 46) {
                    AtlasBigStat(
                        value: "\(library.collections.count)",
                        caption: "folders",
                        tint: theme.primary
                    )
                    AtlasBigStat(
                        value: "\(library.visibleDocuments.count)",
                        caption: "notes",
                        tint: theme.highlight
                    )
                    AtlasBigStat(
                        value: "\(library.lectures.count)",
                        caption: "recordings",
                        tint: theme.warmAccent
                    )
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        AtlasSectionRule(title: "folders")
                        AtlasInlineAction(title: "New", systemImage: "plus") {
                            newCollectionParentID = nil
                            isPresentingNewCollection = true
                        }
                        .fixedSize()
                    }
                    .padding(.bottom, 6)

                    ForEach(library.rootCollections) { collection in
                        Button { selectCollection(collection.id) } label: {
                            FolderRow(
                                collection: collection,
                                noteCount: library.noteCount(in: collection.id, includingSubcollections: true),
                                childCount: library.childCollections(of: collection.id).count
                            )
                        }
                        .buttonStyle(.plain)
                        AtlasFadingRule()
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, AtlasSpace.gutter)
            .padding(.vertical, 44)
        }
        .scrollContentBackground(.hidden)
        .background(theme.canvas)
    }

    private var homeIndexView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Recent")
                    .font(AtlasType.display(30, .bold))
                    .foregroundStyle(theme.textPrimary)
                Text("Where you left off")
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(library.visibleDocuments.prefix(10)) { document in
                        Button {
                            isShowingLectures = false
                            selectedCollectionID = document.collectionID
                            selectedDocumentID = document.id
                        } label: {
                            DocumentRow(document: document, isSelected: false)
                        }
                        .buttonStyle(.plain)
                        AtlasFadingRule()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if library.visibleDocuments.isEmpty {
                    Text("No notes yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private var lecturesPane: some View {
#if os(macOS)
        LecturesView(
            library: library,
            capture: lectureCapture,
            openDocument: openFiledDocument,
            reportError: reportError
        )
#else
        EmptyView()
#endif
    }

#if os(macOS)
    private var lectureSubtitle: String {
        let active = library.lectures.filter { !$0.stage.isTerminal }.count
        if active > 0 { return active == 1 ? "1 in progress" : "\(active) in progress" }
        let total = library.lectures.count
        return total == 1 ? "1 recording" : "\(total) recordings"
    }

    private func showLectures() {
        isShowingLectures = true
        selectedCollectionID = nil
        selectedDocumentID = nil
    }

#endif

    /// Used by the reading view on both platforms, so it lives outside the
    /// macOS-only block. Opening a note from a list starts a fresh trail —
    /// history is for links followed inside a note.
    private func openFiledDocument(_ document: AtlasDocumentSnapshot) {
        isShowingLectures = false
        history = []
        anchorSection = nil
        selectedCollectionID = document.collectionID
        selectedDocumentID = document.id
    }

    /// Follows a link out of `selectedDocument`, remembering the section it was
    /// followed from so Back lands there rather than at the top of the page.
    private func follow(to document: AtlasDocumentSnapshot, leaving sectionID: String?) {
        if let current = selectedDocumentID, current != document.id {
            history.append(NoteVisit(documentID: current, sectionID: sectionID))
        }
        isShowingLectures = false
        anchorSection = nil
        selectedCollectionID = document.collectionID
        selectedDocumentID = document.id
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        guard let document = library.document(id: previous.documentID) else {
            // The note was deleted while you were away; keep unwinding rather
            // than leaving a Back button that does nothing.
            goBack()
            return
        }
        isShowingLectures = false
        selectedCollectionID = document.collectionID
        selectedDocumentID = document.id
        anchorSection = previous.sectionID
    }

    // MARK: - Folder tree

    private var expandedCollections: Set<String> {
        Set(expandedStorage.split(separator: "\u{1F}").map(String.init))
    }

    private func toggleExpanded(_ id: String) {
        var current = expandedCollections
        if !current.insert(id).inserted { current.remove(id) }
        expandedStorage = current.sorted().joined(separator: "\u{1F}")
    }

    private func expand(_ id: String) {
        var current = expandedCollections
        guard current.insert(id).inserted else { return }
        expandedStorage = current.sorted().joined(separator: "\u{1F}")
    }

    /// Selecting a nested folder opens the folders above it, so the selection
    /// is never hidden inside a collapsed parent.
    private func selectCollection(_ id: String) {
        isShowingLectures = false
        for ancestor in library.collectionPath(for: id).dropLast() {
            expand(ancestor.id)
        }
        selectedCollectionID = id
        selectedDocumentID = library.documents(in: id).first?.id
    }

    /// Applies a sidebar drag. A drop that the store refuses — a folder into
    /// its own contents, or past the depth limit — surfaces as a message
    /// rather than silently doing nothing.
    private func applyDrop(_ drop: CollectionDrop) {
        guard library.collections.contains(where: { $0.id == drop.draggedID }) else { return }
        do {
            if let index = drop.index {
                try library.moveCollection(id: drop.draggedID, toParent: drop.parentID, atIndex: index)
            } else {
                try library.moveCollection(id: drop.draggedID, toParent: drop.parentID)
                if let parentID = drop.parentID { expand(parentID) }
            }
        } catch { reportError(error) }
    }

    private func collectionChoices(excluding excludedID: String? = nil) -> [CollectionChoice] {
        var blocked: Set<String> = []
        if let excludedID {
            blocked.insert(excludedID)
            blocked.formUnion(library.descendants(of: excludedID).map(\.id))
        }
        return library.collectionTree().flatMap(\.flattened).map { node in
            CollectionChoice(
                id: node.id,
                title: node.collection.title,
                depth: node.depth,
                isSelectable: !blocked.contains(node.id)
            )
        }
    }

    /// Whether this class, or a folder above it, has anything saved.
    private func hasContext(_ collection: AtlasCollectionSnapshot) -> Bool {
        library.collectionPath(for: collection.id).contains {
            library.courseContext(for: $0.id)?.hasBriefing == true
        } || !library.courseAttachments(for: collection.id).isEmpty
    }

    /// Context set on folders above this one, which applies here too.
    private func inheritedContext(for collection: AtlasCollectionSnapshot) -> [(title: String, briefing: String)] {
        library.collectionPath(for: collection.id)
            .dropLast()
            .compactMap { ancestor in
                guard let saved = library.courseContext(for: ancestor.id), saved.hasBriefing else { return nil }
                return (ancestor.title, saved.briefing)
            }
    }

    private func headerCountLabel(for collection: AtlasCollectionSnapshot) -> String {
        let shown = visibleDocuments.count == 1 ? "1 note" : "\(visibleDocuments.count) notes"
        let children = library.childCollections(of: collection.id).count
        guard children > 0 else { return shown }
        return "\(shown) · \(children == 1 ? "1 folder" : "\(children) folders") inside"
    }

    private func isEmptyCollection(_ collection: AtlasCollectionSnapshot) -> Bool {
        library.noteCount(in: collection.id, includingSubcollections: false) == 0
            && library.childCollections(of: collection.id).isEmpty
    }

    private func contentsDescription(for collection: AtlasCollectionSnapshot) -> String {
        let notes = library.noteCount(in: collection.id, includingSubcollections: false)
        let folders = library.childCollections(of: collection.id).count
        var parts: [String] = [notes == 1 ? "1 note" : "\(notes) notes"]
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders) folders") }
        return parts.joined(separator: " · ")
    }

    private func repairSelection() {
#if os(macOS)
        if isShowingLectures { return }
#endif
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--atlas-open-first-note"),
           selectedDocumentID == nil,
           let firstDocument = library.documents.first {
            selectedCollectionID = firstDocument.collectionID
            selectedDocumentID = firstDocument.id
            return
        }
#endif
        if let selectedCollectionID,
           !library.collections.contains(where: { $0.id == selectedCollectionID }) {
            self.selectedCollectionID = nil
            selectedDocumentID = nil
            return
        }
        if selectedCollectionID == nil { return }
        if let selectedDocumentID,
           library.document(id: selectedDocumentID)?.collectionID == self.selectedCollectionID {
            return
        }
        selectedDocumentID = visibleDocuments.first?.id
    }
}
