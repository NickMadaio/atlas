import AVFoundation
import Foundation

#if os(macOS)

/// Captures lecture audio from the Mac's input device.
///
/// Everything is written to disk as it arrives, at 16 kHz mono — the format
/// speech recognition actually wants, and about 115 MB for a three-hour day
/// rather than several gigabytes. If the audio device changes mid-lecture the
/// engine stops, and whatever was captured up to that point is already saved.
@MainActor
final class LectureRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case finishing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var inputLevel: Float = 0
    /// True once nothing audible has arrived for a while. Says out loud what a
    /// flat meter only implies, so a silent input is caught in the first
    /// minute rather than discovered after the lecture.
    @Published private(set) var isHearingNothing = false
    @Published private(set) var interruption: String?

    /// Called when capture ends for a reason the user did not ask for. Without
    /// this the pipeline never learns the recording finished: the lecture is
    /// left mid-flight and the on-screen bubble keeps claiming to record.
    var onUnexpectedStop: (() -> Void)?

    private let engine = AVAudioEngine()
    private var sink: RecordingSink?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private var configurationObserver: NSObjectProtocol?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static var permissionDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .denied || status == .restricted
    }

    func start(writingTo url: URL) throws {
        guard state == .idle else { throw LectureRecorderError.alreadyRecording }
        interruption = nil

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw LectureRecorderError.noInputDevice
        }

        let sink = try RecordingSink(url: url, inputFormat: inputFormat)
        self.sink = sink

        // Explicitly @Sendable: the tap block is not marked Sendable in the SDK,
        // so inside this @MainActor type Swift would infer main-actor isolation
        // and insert an executor check that traps on the realtime audio thread.
        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { @Sendable buffer, _ in
            sink.accept(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.sink = nil
            try? sink.close()
            throw LectureRecorderError.engineFailed(error.localizedDescription)
        }

        startedAt = .now
        isPaused = false
        state = .recording
        observeConfigurationChanges()
        startMeter()
    }

    /// Pauses capture without ending the lecture. The engine keeps running so
    /// resuming is instant; incoming audio is simply not written, which is what
    /// "pause" has to mean for a recording — the gap disappears rather than
    /// becoming silence the transcriber has to chew through.
    func setPaused(_ paused: Bool) {
        guard state == .recording else { return }
        sink?.setPaused(paused)
        isPaused = paused
        if paused { inputLevel = 0 }
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    /// Stops capture and returns how much audio was written. Always safe to
    /// call; a recording that already stopped itself still reports its length.
    @discardableResult
    func stop() -> TimeInterval {
        guard state != .idle else { return elapsed }
        state = .finishing

        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        stopMeter()
        removeConfigurationObserver()

        let written = sink?.duration ?? elapsed
        try? sink?.close()
        sink = nil

        elapsed = written
        inputLevel = 0
        isPaused = false
        isHearingNothing = false
        state = .idle
        startedAt = nil
        return written
    }

    // MARK: - Meter and interruptions

    private func startMeter() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let sink else { return }
                elapsed = sink.duration
                inputLevel = sink.level
                isHearingNothing = !isPaused && elapsed > 8 && sink.secondsSinceSound > 8
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    /// Unplugging headphones or switching input mid-lecture reconfigures the
    /// engine. Stopping deliberately keeps every minute captured so far rather
    /// than leaving a half-open file behind.
    private func observeConfigurationChanges() {
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, state == .recording else { return }
                interruption = "The audio input changed, so recording stopped. Everything captured up to that point was saved."
                onUnexpectedStop?()
            }
        }
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }
}

/// Owns the output file and the format conversion. Lives off the main actor
/// because the audio tap calls it from a realtime thread.
private final class RecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var currentLevel: Float = 0
    private var isPaused = false
    private var lastSoundAt = Date.now

    init(url: URL, inputFormat: AVAudioFormat) throws {
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw LectureRecorderError.unsupportedFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw LectureRecorderError.unsupportedFormat
        }
        outputFormat = target
        self.converter = converter

        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: target.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw LectureRecorderError.fileNotWritable(error.localizedDescription)
        }
    }

    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(frames) / outputFormat.sampleRate
    }

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return currentLevel
    }

    var secondsSinceSound: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date.now.timeIntervalSince(lastSoundAt)
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isPaused = paused
        if paused { currentLevel = 0 }
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let paused = isPaused
        lock.unlock()
        guard !paused else { return }

        let meter = Self.meterLevel(of: buffer)
        let capacity = AVAudioFrameCount(
            (Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate).rounded(.up) + 1_024
        )
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // The converter's input block is declared @Sendable, so the pending
        // buffer is handed over through a reference rather than captured as a
        // mutable local. The block still runs synchronously on this thread.
        let pending = PendingBuffer(buffer)
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            guard let next = pending.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return next
        }
        guard conversionError == nil, converted.frameLength > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        // Fast attack, slow decay: a meter that snaps back to zero between
        // syllables reads as "hearing nothing" even when it is not.
        currentLevel = max(meter, currentLevel * 0.82)
        // Low enough that a quiet room with background hiss never trips the
        // warning; the warning is for a muted or wrong input, not a quiet one.
        if meter >= 0.035 { lastSoundAt = .now }
        guard let file else { return }
        do {
            try file.write(from: converted)
            frames += AVAudioFramePosition(converted.frameLength)
        } catch {
            // A write failure ends capture rather than spinning on every
            // buffer; the audio already on disk stays valid and readable.
            self.file = nil
        }
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        file = nil
    }

    /// Reads every channel, not just the first: on several interfaces channel
    /// zero is silent and only channel one carries the microphone, which made
    /// a working recording look like it was hearing nothing.
    private static func meterLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))

        var peak: Float = 0
        var sumSquares: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for index in 0..<frames {
                let magnitude = abs(samples[index])
                if magnitude > peak { peak = magnitude }
                sumSquares += magnitude * magnitude
            }
        }

        let rms = (sumSquares / Float(frames * channelCount)).squareRoot()
        // Peak makes speech visible; RMS keeps a single click from pinning it.
        let combined = max(rms * 2.5, peak * 0.7)
        // A laptop mic across a lecture theatre sits near -55 dBFS, so the
        // usable range starts far lower than a music meter's would.
        let decibels = 20 * log10(max(combined, 0.000_000_1))
        return min(1, max(0, (decibels + 62) / 56))
    }
}

/// Hands one buffer to the converter exactly once.
private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

enum LectureRecorderError: LocalizedError {
    case alreadyRecording
    case noInputDevice
    case unsupportedFormat
    case fileNotWritable(String)
    case engineFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Atlas is already recording a lecture."
        case .noInputDevice:
            "No microphone is available. Choose an input device in System Settings › Sound."
        case .unsupportedFormat:
            "Atlas could not set up the microphone in a format it can record."
        case let .fileNotWritable(reason):
            "Atlas could not create the recording file: \(reason)"
        case let .engineFailed(reason):
            "Atlas could not start recording: \(reason)"
        case .permissionDenied:
            "Atlas does not have microphone access. Grant it in System Settings › Privacy & Security › Microphone."
        }
    }
}

#endif
