import AtlasCore
import SwiftUI

#if os(macOS)

/// The record control itself. Compact enough to live permanently in the
/// sidebar, because the moment you need it — a lecture starting — is not the
/// moment to go looking through menus.
struct LectureRecordBar: View {
    @ObservedObject var capture: LectureCaptureModel
    @ObservedObject private var recorder: LectureRecorder
    var onShowLectures: () -> Void
    @Environment(\.atlasPalette) private var theme
    @FocusState private var hintFocused: Bool

    init(capture: LectureCaptureModel, onShowLectures: @escaping () -> Void) {
        self.capture = capture
        recorder = capture.recorder
        self.onShowLectures = onShowLectures
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch capture.phase {
            case .recording:
                recordingControls
            case let .working(label, fraction):
                workingControls(label: label, fraction: fraction)
            case let .finished(message):
                resultControls(message: message, isError: false)
            case let .failed(message):
                resultControls(message: message, isError: true)
            case .idle:
                idleControls
            }

            if let interruption = recorder.interruption {
                Text(interruption)
                    .font(.caption2)
                    .foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(capture.isRecording ? theme.danger : theme.divider, lineWidth: capture.isRecording ? 1.5 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.caption.weight(.bold))
                .foregroundStyle(capture.isRecording ? theme.danger : theme.primary)
            Text("LECTURE")
                .font(.system(size: 10.5, weight: .black))
                .tracking(1.1)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Button(action: onShowLectures) {
                Text("History")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show recorded lectures")
        }
    }

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Which class? (optional)", text: $capture.courseHint)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($hintFocused)
                .padding(.horizontal, 9)
                .frame(height: 29)
                .background(theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(theme.divider, lineWidth: 1) }
                .accessibilityLabel("Class label for this recording")

            Button {
                hintFocused = false
                Task { await capture.startRecording() }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                    Text("Record lecture")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(theme.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!capture.canRecord)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Start recording this lecture (⇧⌘R)")
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                PulsingDot(color: theme.danger)
                Text(AtlasLectureSegment.timecode(for: recorder.elapsed))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                LevelMeter(level: recorder.inputLevel, color: recorder.isHearingNothing ? theme.warmAccent : theme.danger)
            }

            if recorder.isHearingNothing {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.warmAccent)
                    Text("No sound is reaching Atlas. Check the input device in System Settings › Sound.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.warmAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                capture.stopRecording()
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                    Text("End lecture")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(theme.primaryStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Stop recording and write the notes (⇧⌘R)")
        }
    }

    private func workingControls(label: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(theme.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let modelName = capture.modelName {
                Text(modelName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            }
            Button("Stop writing notes") { capture.cancelWork() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func resultControls(message: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(isError ? theme.danger : theme.primary)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(isError ? "See lectures" : "Open notes", action: onShowLectures)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Dismiss") { capture.cancelWork() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var isOn = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .opacity(isOn ? 1 : 0.28)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isOn)
            .onAppear { isOn = true }
            .accessibilityLabel("Recording")
    }
}

private struct LevelMeter: View {
    let level: Float
    let color: Color
    private let barCount = 9
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index + 1) / Float(barCount)
                RoundedRectangle(cornerRadius: 1)
                    // Unlit segments are neutral rather than a washed-out
                    // version of the lit colour.
                    .fill(level >= threshold ? color : theme.divider)
                    .frame(width: 2.5, height: 5 + CGFloat(index) * 1.4)
            }
        }
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}


/// The menu bar control. A lecture starts before you have the app window
/// open, so starting and ending one has to be reachable without it.
struct LectureMenuBarView: View {
    @ObservedObject var capture: LectureCaptureModel
    @ObservedObject private var recorder: LectureRecorder
    @Environment(\.openWindow) private var openSwiftUIWindow

    init(capture: LectureCaptureModel) {
        self.capture = capture
        recorder = capture.recorder
    }

    /// Brings Atlas forward, creating a window if the last one was closed.
    private func openWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let existing = NSApplication.shared.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        openSwiftUIWindow(id: AtlasApp.mainWindowID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(capture.isRecording ? Color.red : Color.accentColor)
                Text(statusTitle)
                    .font(.headline)
                Spacer()
            }

            switch capture.phase {
            case .recording:
                Text(AtlasLectureSegment.timecode(for: recorder.elapsed))
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                Button("End lecture") { capture.stopRecording() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

            case let .working(label, fraction):
                ProgressView(value: fraction) { Text(label).font(.caption) }
                    .frame(maxWidth: .infinity)

            case let .finished(message):
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Atlas", action: openWindow)
                    .buttonStyle(.borderedProminent)

            case let .failed(message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Atlas", action: openWindow)

            case .idle:
                TextField("Which class? (optional)", text: $capture.courseHint)
                    .textFieldStyle(.roundedBorder)
                Button("Record lecture") {
                    Task { await capture.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!capture.canRecord)
            }

            Divider()
            Button("Open Atlas", action: openWindow)
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 260)
    }

    private var statusTitle: String {
        switch capture.phase {
        case .recording: "Recording lecture"
        case .working: "Writing notes"
        case .finished: "Lecture filed"
        case .failed: "Needs attention"
        case .idle: "Atlas lectures"
        }
    }
}

#endif
