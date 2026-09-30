import AVFoundation
import AtlasCore
import Foundation

#if os(macOS)

/// Drives one lecture from "press record" to two filed notes.
///
/// The ordering is deliberate. Audio is on disk before anything else happens,
/// and the transcript is saved the instant it exists — so every later step is
/// allowed to fail without costing a lecture that cannot be attended twice.
@MainActor
final class LectureCaptureModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case working(label: String, fraction: Double)
        case finished(message: String)
        case failed(message: String)

        var isBusy: Bool {
            if case .working = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var activeLectureID: String?
    @Published private(set) var lastFiled: AtlasFiledLecture?
    @Published private(set) var modelName: String?
    @Published var courseHint = ""

    let recorder = LectureRecorder()

    private let library: AtlasLibraryStore
    private let settings: AtlasSettingsStore
    private let audioDirectory: URL
    private let attachmentsDirectory: URL
    private let bubble = LectureBubbleController()
    private var work: Task<Void, Never>?

    init(
        library: AtlasLibraryStore,
        settings: AtlasSettingsStore,
        fileManager: FileManager = .default
    ) {
        self.library = library
        self.settings = settings
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        audioDirectory = support.appending(path: "Atlas/Lectures", directoryHint: .isDirectory)
        attachmentsDirectory = support.appending(path: "Atlas/Attachments", directoryHint: .isDirectory)
        for directory in [audioDirectory, attachmentsDirectory] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        // An audio device change ends capture on its own; finish the lecture
        // properly so the transcript still gets written.
        recorder.onUnexpectedStop = { [weak self] in
            self?.stopRecording()
        }

        recoverLostLectures()
        recoverInterruptedLectures()
    }

    /// Puts back lectures whose rows were lost while their notes survived.
    ///
    /// Opening this library with a build of Atlas older than the lecture
    /// feature migrates the store down to that model and drops the lecture and
    /// attachment tables. The audio stays on disk and the source notes stay in
    /// the library, so the recording can be rebuilt from its own output.
    ///
    /// Runs at every launch and does nothing when there is nothing to find.
    private func recoverLostLectures() {
        let audioFiles = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)) ?? []
        )
        guard let recovered = try? library.recoverLecturesFromSourceNotes(
            availableAudioFileNames: audioFiles
        ), !recovered.isEmpty else { return }

        for lecture in recovered {
            reregisterAttachments(for: lecture)
        }
    }

    /// Re-reads the files still sitting in a recovered lecture's attachment
    /// folder. The stored names are opaque, so the display names the source
    /// note recorded are used when they line up, and the file's own name when
    /// they do not — a wrong name would be worse than an honest one.
    private func reregisterAttachments(for lecture: AtlasLibraryStore.LectureRecovery) {
        let folder = attachmentsDirectory.appending(path: lecture.lectureID, directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        guard !files.isEmpty else { return }

        // Consumed as they are matched, so two files of the same type cannot
        // both claim the same recorded name.
        var unclaimed = lecture.attachmentNames
        for fileName in files {
            let url = folder.appending(path: fileName)
            let extraction = AttachmentTextExtractor.extract(from: url)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // Matched by file type: the note lists names in the order they were
            // added, which is not the order the folder returns them in.
            let suffix = (fileName as NSString).pathExtension.lowercased()
            let displayName: String
            if let match = unclaimed.firstIndex(where: { ($0 as NSString).pathExtension.lowercased() == suffix }) {
                displayName = unclaimed.remove(at: match)
            } else {
                displayName = fileName
            }

            try? library.addAttachment(
                lectureID: lecture.lectureID,
                fileName: fileName,
                displayName: displayName,
                extractedText: extraction.text,
                pages: extraction.pages,
                byteSize: size,
                extractionNote: extraction.note
            )
        }
    }

    /// A lecture left mid-flight by a crash or a force quit still has its audio
    /// on disk. Nothing can be in progress at launch, so anything claiming to
    /// be is surfaced with its real state and a working Try again.
    private func recoverInterruptedLectures() {
        for lecture in library.lectures where !lecture.stage.isTerminal {
            let seconds = audioDuration(for: lecture)
            let reason: String
            if lecture.hasUsableTranscript {
                reason = "Atlas stopped before these notes were written. The transcript was kept — choose Try again."
            } else if seconds >= 1 {
                reason = "Atlas stopped while recording. \(AtlasLectureSegment.timecode(for: seconds)) of audio was kept — choose Try again to transcribe it."
            } else {
                reason = "Atlas stopped before any audio was captured."
            }

            // Record the real length so recovered notes do not claim 0:00.
            if seconds > lecture.durationSeconds {
                try? library.finishRecording(
                    lectureID: lecture.id,
                    durationSeconds: seconds,
                    endedAt: lecture.endedAt ?? .now
                )
            }
            try? library.updateLectureStage(id: lecture.id, stage: .failed, failureReason: reason)
        }
    }

    private func audioDuration(for lecture: AtlasLectureSnapshot) -> Double {
        guard let file = try? AVAudioFile(forReading: audioURL(for: lecture)) else { return 0 }
        let rate = file.fileFormat.sampleRate
        guard rate > 0 else { return 0 }
        return Double(file.length) / rate
    }

    var isRecording: Bool { recorder.state == .recording }

    var canRecord: Bool {
        recorder.state == .idle && !phase.isBusy
    }

    func audioURL(for lecture: AtlasLectureSnapshot) -> URL {
        audioDirectory.appending(path: lecture.audioFileName)
    }

    // MARK: - Recording

    func startRecording() async {
        guard canRecord else { return }
        guard await LectureRecorder.requestPermission() else {
            phase = .failed(message: LectureRecorderError.permissionDenied.localizedDescription)
            return
        }

        do {
            let hint = courseHint.trimmingCharacters(in: .whitespacesAndNewlines)
            let lecture = try library.beginLecture(courseHint: hint.isEmpty ? nil : hint)
            try recorder.start(writingTo: audioDirectory.appending(path: lecture.audioFileName))

            activeLectureID = lecture.id
            lastFiled = nil
            phase = .recording
            bubble.show(capture: self)
        } catch {
            bubble.hide()
            phase = .failed(message: error.localizedDescription)
            if let activeLectureID { try? library.updateLectureStage(id: activeLectureID, stage: .failed, failureReason: error.localizedDescription) }
            activeLectureID = nil
        }
    }

    func stopRecording() {
        guard let lectureID = activeLectureID else { return }
        let duration = recorder.stop()
        bubble.hide()
        activeLectureID = nil

        guard duration >= 2 else {
            discard(lectureID: lectureID)
            phase = .failed(message: "That recording was under two seconds, so nothing was saved.")
            return
        }

        do {
            try library.finishRecording(lectureID: lectureID, durationSeconds: duration, endedAt: .now)
        } catch {
            phase = .failed(message: error.localizedDescription)
            return
        }

        process(lectureID: lectureID)
    }

    /// Runs, or re-runs, everything after the audio: transcription, note
    /// writing, and filing. Safe to call on a lecture that already has notes.
    func process(lectureID: String) {
        work?.cancel()
        work = Task { [weak self] in
            await self?.runPipeline(lectureID: lectureID)
        }
    }

    func cancelWork() {
        work?.cancel()
        work = nil
        phase = .idle
    }

    func discard(lectureID: String, includingNotes: Bool = false) {
        if let lecture = library.lecture(id: lectureID) {
            try? FileManager.default.removeItem(at: audioURL(for: lecture))
        }
        try? FileManager.default.removeItem(at: attachmentsDirectory.appending(path: lectureID, directoryHint: .isDirectory))
        try? library.deleteLecture(id: lectureID, includingNotes: includingNotes)
    }

    // MARK: - Importing

    /// Turns text the student already has into Atlas notes.
    ///
    /// Runs the identical pipeline a recording runs, minus transcription, so
    /// imported notes get the same structure, review and quiz rather than a
    /// second-class version of them.
    @discardableResult
    func importText(_ text: String, title: String, courseHint: String?) -> String? {
        do {
            let lecture = try library.beginImport(text: text, title: title, courseHint: courseHint)
            process(lectureID: lecture.id)
            return lecture.id
        } catch {
            phase = .failed(message: error.localizedDescription)
            return nil
        }
    }

    /// Reads a file the student picked, without copying it into Atlas — an
    /// import keeps its text, not the document, because the document is
    /// already wherever they keep it.
    func readTextForImport(from url: URL) -> Result<String, Error> {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let extraction = AttachmentTextExtractor.extract(from: url)
        guard extraction.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else {
            return .failure(
                AtlasSimpleError(
                    message: extraction.note
                        ?? "\(url.lastPathComponent): no readable text could be taken from this file."
                )
            )
        }
        return .success(extraction.text)
    }

    // MARK: - Attachments

    func attachmentURL(for attachment: AtlasAttachmentSnapshot) -> URL {
        attachmentsDirectory
            .appending(path: attachment.collectionID ?? attachment.lectureID, directoryHint: .isDirectory)
            .appending(path: attachment.fileName)
    }

    /// Course material — a syllabus, a module outline — attached to the class
    /// rather than to one recording, so every lecture in it is written knowing
    /// the same things.
    @discardableResult
    func attachCourseFiles(_ urls: [URL], to collectionID: String) -> [String] {
        copyIn(urls, folderName: collectionID) { storedName, displayName, extraction, size in
            try self.library.addCourseAttachment(
                collectionID: collectionID,
                fileName: storedName,
                displayName: displayName,
                extractedText: extraction.text,
                pages: extraction.pages,
                byteSize: size,
                extractionNote: extraction.note
            )
        }
    }

    /// Corrections and context for one recording. Saving does not rewrite the
    /// notes on its own — rewriting is the caller's decision, because it costs
    /// minutes of model time.
    func setContext(_ note: String, for lectureID: String) throws {
        try library.setLectureContext(lectureID: lectureID, note: note)
    }

    /// Copies chosen files into Atlas's own storage and reads their text.
    ///
    /// The copy matters: a file picked from Downloads can be moved or deleted
    /// tomorrow, and a lecture's supporting material should not evaporate with
    /// it. Returns what could not be added, so the caller can say so.
    @discardableResult
    func attachFiles(_ urls: [URL], to lectureID: String) -> [String] {
        copyIn(urls, folderName: lectureID) { storedName, displayName, extraction, size in
            try self.library.addAttachment(
                lectureID: lectureID,
                fileName: storedName,
                displayName: displayName,
                extractedText: extraction.text,
                pages: extraction.pages,
                byteSize: size,
                extractionNote: extraction.note
            )
        }
    }

    /// Copies chosen files into Atlas's own storage and reads their text.
    ///
    /// The copy matters: a file picked from Downloads can be moved or deleted
    /// tomorrow, and supporting material should not evaporate with it. A file
    /// whose record cannot be written is removed again rather than left as a
    /// copy nothing refers to. Returns what could not be added.
    private func copyIn(
        _ urls: [URL],
        folderName: String,
        record: (String, String, AttachmentTextExtractor.Result, Int) throws -> Void
    ) -> [String] {
        var problems: [String] = []
        let folder = attachmentsDirectory.appending(path: folderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let storedName = "\(UUID().uuidString.lowercased()).\(url.pathExtension.lowercased())"
            let destination = folder.appending(path: storedName)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                problems.append("\(url.lastPathComponent): could not be copied into Atlas.")
                continue
            }

            let extraction = AttachmentTextExtractor.extract(from: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            do {
                try record(storedName, url.lastPathComponent, extraction, size)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return problems
    }

    func removeAttachment(_ attachment: AtlasAttachmentSnapshot) {
        try? FileManager.default.removeItem(at: attachmentURL(for: attachment))
        try? library.deleteAttachment(id: attachment.id)
    }

    // MARK: - Pipeline

    private func runPipeline(lectureID: String) async {
        guard var lecture = library.lecture(id: lectureID) else { return }

        if lecture.durationSeconds <= 0 {
            let measured = audioDuration(for: lecture)
            if measured > 0 {
                try? library.finishRecording(
                    lectureID: lectureID,
                    durationSeconds: measured,
                    endedAt: lecture.endedAt ?? .now
                )
                lecture = library.lecture(id: lectureID) ?? lecture
            }
        }

        // 1. Transcribe, unless a usable transcript already exists.
        if !lecture.hasUsableTranscript {
            report(.working(label: "Preparing transcription", fraction: 0.02))
            try? library.updateLectureStage(id: lectureID, stage: .transcribing)

            guard #available(macOS 26.0, *), LectureTranscriber.isSupported else {
                fail(lectureID: lectureID, message: LectureTranscriptionError.unavailable.localizedDescription)
                return
            }

            do {
                let segments = try await LectureTranscriber.transcribe(
                    fileURL: audioURL(for: lecture),
                    onProgress: { [weak self] update in
                        Task { @MainActor in
                            self?.report(.working(label: update.label, fraction: 0.05 + update.fraction * 0.5))
                        }
                    }
                )
                try Task.checkCancellation()
                try library.attachTranscript(
                    lectureID: lectureID,
                    segments: segments,
                    transcriptText: segments.map(\.text).joined(separator: " "),
                    durationSeconds: lecture.durationSeconds,
                    endedAt: lecture.endedAt ?? .now
                )
            } catch is CancellationError {
                report(.idle)
                return
            } catch {
                fail(lectureID: lectureID, message: error.localizedDescription)
                return
            }
            guard let refreshed = library.lecture(id: lectureID) else { return }
            lecture = refreshed
        }

        // 2. Write notes with a local model, falling back to the transcript
        //    itself rather than leaving the lecture unfiled.
        report(.working(label: "Looking for a local model", fraction: 0.58))
        try? library.updateLectureStage(id: lectureID, stage: .structuring)

        var structure: LectureStructure
        var modelIdentifier: String?

        // Standing facts about the course, assembled before a word is read.
        // This is what stops a Python course's notes filling up with Java.
        let briefing = library.briefing(forLecture: lectureID)
        var placement: LectureClassifier.Decision?

        if let client = await LectureModelResolver.resolve() {
            modelName = client.identifier
            let service = LectureStructuringService(client: client)
            do {
                structure = try await service.makeStructure(
                    segments: lecture.segments,
                    transcriptText: lecture.transcriptText,
                    hint: lecture.courseHint,
                    durationSeconds: lecture.durationSeconds,
                    attachments: library.attachmentTexts(for: lectureID),
                    briefing: briefing,
                    skills: settings.skills,
                    format: settings.noteFormat,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.report(.working(label: progress.stageLabel, fraction: 0.6 + progress.fraction * 0.28))
                        }
                    }
                )
                modelIdentifier = client.identifier

                // Which folder is a judgement about what the folders mean, so
                // the model gets the tree and a vote. A reply that does not
                // check out is dropped and token matching decides instead.
                report(.working(label: "Choosing a folder", fraction: 0.9))
                placement = await service.decidePlacement(
                    structure: structure,
                    hint: lecture.courseHint,
                    options: library.placementOptions(),
                    skills: settings.skills
                )
            } catch is CancellationError {
                report(.idle)
                return
            } catch {
                structure = fallbackStructure(for: lecture)
            }
        } else {
            modelName = nil
            structure = fallbackStructure(for: lecture)
        }

        // 3. File into a class and write both notes.
        report(.working(label: "Filing into a class", fraction: 0.95))
        try? library.updateLectureStage(id: lectureID, stage: .filing)

        do {
            let filed = try library.fileLecture(
                lectureID: lectureID,
                structure: structure,
                transcriptionEngine: transcriptionEngineName,
                modelIdentifier: modelIdentifier,
                proposedDecision: placement,
                format: settings.noteFormat
            )
            lastFiled = filed
            let suffix = modelIdentifier == nil
                ? " No local model was available, so the notes are transcript-only."
                : ""
            report(.finished(message: "Filed into \(filed.collectionTitle).\(suffix)"))
        } catch {
            fail(lectureID: lectureID, message: error.localizedDescription)
        }
    }

    private func fallbackStructure(for lecture: AtlasLectureSnapshot) -> LectureStructure {
        LectureFallbackStructure.build(
            segments: lecture.segments,
            transcriptText: lecture.transcriptText,
            hint: lecture.courseHint,
            durationSeconds: lecture.durationSeconds
        )
    }

    private var transcriptionEngineName: String {
        if #available(macOS 26.0, *) { return LectureTranscriber.engineName }
        return "Unavailable"
    }

    private func report(_ phase: Phase) {
        self.phase = phase
    }

    private func fail(lectureID: String, message: String) {
        try? library.updateLectureStage(id: lectureID, stage: .failed, failureReason: message)
        phase = .failed(message: message)
    }
}

/// Picks the best local model available right now. Ollama first when it is
/// running, because a student's own 20B model writes far better notes than
/// anything bundled; Apple's on-device model otherwise, so the feature still
/// works with nothing installed.
enum LectureModelResolver {
    static let preferredModelKey = "atlas.lecture.preferredOllamaModel"

    static func resolve() async -> (any LectureModelClient)? {
        let preferred = UserDefaults.standard.string(forKey: preferredModelKey)
        if let ollama = await OllamaModelClient.discover(preferring: preferred) {
            return ollama
        }
        if #available(macOS 26.0, *), AppleLocalModelClient.isSupported {
            return AppleLocalModelClient()
        }
        return nil
    }

    static func availableModelNames() async -> [String] {
        await OllamaModelClient.installedModels() ?? []
    }
}

#endif
