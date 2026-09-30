import AVFoundation
import CoreMedia
import Foundation
import Speech

#if os(macOS) || os(iOS)

/// Turns a recorded lecture into timed text using Apple's on-device speech
/// models. Nothing is uploaded: the models run locally, which is the only way
/// a recording of a room full of named people should be handled.
@available(macOS 26.0, iOS 26.0, *)
public enum LectureTranscriber {
    public static let engineName = "Apple Speech (on device)"

    public struct Update: Sendable {
        public let label: String
        public let fraction: Double
    }

    public static var isSupported: Bool { SpeechTranscriber.isAvailable }

    public static func transcribe(
        fileURL: URL,
        locale: Locale = .current,
        onProgress: @escaping @Sendable (Update) -> Void = { _ in }
    ) async throws -> [AtlasLectureSegment] {
        guard SpeechTranscriber.isAvailable else {
            throw LectureTranscriptionError.unavailable
        }

        let resolved = await resolveLocale(locale)
        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        try await installAssetsIfNeeded(for: transcriber, onProgress: onProgress)
        _ = try? await AssetInventory.reserve(locale: resolved)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw LectureTranscriptionError.unreadableRecording(error.localizedDescription)
        }
        let sampleRate = file.fileFormat.sampleRate
        let totalSeconds = sampleRate > 0 ? Double(file.length) / sampleRate : 0
        guard totalSeconds > 0.5 else {
            throw LectureTranscriptionError.recordingTooShort
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> [AtlasLectureSegment] in
            var segments: [AtlasLectureSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = seconds(result.range.start)
                let end = max(start, seconds(result.range.end))
                segments.append(AtlasLectureSegment(start: start, end: end, text: text))
                onProgress(
                    Update(
                        label: "Transcribing \(AtlasLectureSegment.timecode(for: end)) of \(AtlasLectureSegment.timecode(for: totalSeconds))",
                        fraction: min(0.99, end / totalSeconds)
                    )
                )
            }
            return segments
        }

        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw LectureTranscriptionError.failed(error.localizedDescription)
        }

        let segments = try await collector.value
        guard !segments.isEmpty else { throw LectureTranscriptionError.noSpeechFound }
        onProgress(Update(label: "Transcription finished", fraction: 1))
        return segments
    }

    /// Falls back to US English rather than failing outright when the Mac's
    /// own locale has no speech model.
    private static func resolveLocale(_ locale: Locale) async -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return match
        }
        let fallback = Locale(identifier: "en_US")
        return await SpeechTranscriber.supportedLocale(equivalentTo: fallback) ?? fallback
    }

    private static func installAssetsIfNeeded(
        for transcriber: SpeechTranscriber,
        onProgress: @escaping @Sendable (Update) -> Void
    ) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else { return }
        guard status != .unsupported else {
            throw LectureTranscriptionError.localeUnsupported
        }

        onProgress(Update(label: "Downloading the on-device speech model", fraction: 0))
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return
            }
            try await request.downloadAndInstall()
        } catch {
            throw LectureTranscriptionError.assetInstallFailed(error.localizedDescription)
        }
    }

    private static func seconds(_ time: CMTime) -> Double {
        guard time.isNumeric else { return 0 }
        return max(0, CMTimeGetSeconds(time))
    }
}

public enum LectureTranscriptionError: LocalizedError {
    case unavailable
    case localeUnsupported
    case assetInstallFailed(String)
    case unreadableRecording(String)
    case recordingTooShort
    case noSpeechFound
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "On-device transcription is not available on this Mac. The recording was kept."
        case .localeUnsupported:
            "Apple has no on-device speech model for this language. The recording was kept."
        case let .assetInstallFailed(reason):
            "The on-device speech model could not be installed: \(reason)"
        case let .unreadableRecording(reason):
            "The recording could not be opened: \(reason)"
        case .recordingTooShort:
            "That recording is too short to transcribe."
        case .noSpeechFound:
            "No speech was found in the recording. Check that the right microphone was selected."
        case let .failed(reason):
            "Transcription stopped: \(reason)"
        }
    }
}

#endif
