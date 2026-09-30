import AtlasCore
import SwiftUI

#if os(macOS)
import AppKit

/// The small always-visible recording indicator.
///
/// A lecture is recorded with Atlas in the background, behind slides or a
/// browser. Without something on screen the only evidence that recording is
/// running is memory, which is exactly the thing that fails in a lecture. This
/// floats above everything, on every Space, and can pause or end the recording
/// without switching apps.
struct RecordingBubbleView: View {
    @ObservedObject var capture: LectureCaptureModel
    @ObservedObject private var recorder: LectureRecorder
    @State private var isPulsing = false

    init(capture: LectureCaptureModel) {
        self.capture = capture
        recorder = capture.recorder
    }

    private var isPaused: Bool { recorder.isPaused }

    var body: some View {
        HStack(spacing: 10) {
            indicator

            VStack(alignment: .leading, spacing: 0) {
                Text(AtlasLectureSegment.timecode(for: recorder.elapsed))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    if !isPaused {
                        BubbleMeter(level: recorder.inputLevel, isSilent: recorder.isHearingNothing)
                    }
                    Text(statusText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(recorder.isHearingNothing && !isPaused ? .orange : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 2)

            BubbleButton(
                symbol: isPaused ? "play.fill" : "pause.fill",
                tint: .primary,
                help: isPaused ? "Resume recording" : "Pause recording"
            ) {
                recorder.togglePause()
            }

            BubbleButton(symbol: "stop.fill", tint: .red, help: "End lecture and write notes") {
                capture.stopRecording()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: LectureBubbleController.size.width, height: LectureBubbleController.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPaused ? "Lecture recording paused" : "Recording a lecture")
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(isPaused ? Color.orange.opacity(0.18) : Color.red.opacity(0.18))
                .frame(width: 26, height: 26)
            Circle()
                .fill(isPaused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(isPaused ? 1 : (isPulsing ? 1 : 0.25))
        }
        .animation(
            isPaused ? .default : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
    }

    /// Falls back to the class label when there is one, so a glance says which
    /// lecture is being recorded rather than just that one is.
    private var statusText: String {
        if isPaused { return "Paused" }
        if recorder.isHearingNothing { return "No sound" }
        let hint = capture.courseHint.trimmingCharacters(in: .whitespacesAndNewlines)
        return hint.isEmpty ? "Recording" : hint
    }
}

/// A few bars that move with the room. The point is not precision — it is
/// being able to tell at a glance that the microphone is live.
private struct BubbleMeter: View {
    let level: Float
    let isSilent: Bool

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Float(index + 1) / 5
                Capsule()
                    .fill(isSilent ? Color.orange.opacity(0.3) : (level >= threshold ? Color.green : Color.secondary.opacity(0.25)))
                    .frame(width: 2, height: 4 + CGFloat(index) * 1.5)
            }
        }
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

private struct BubbleButton: View {
    let symbol: String
    let tint: Color
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(
                    .primary.opacity(isHovering ? 0.12 : 0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A panel that floats over other apps without stealing focus from them.
private final class BubblePanel: NSPanel {
    // Borderless panels refuse key status by default, which would leave the
    // pause and stop buttons unclickable.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LectureBubbleController {
    static let size = CGSize(width: 218, height: 54)
    private static let originKey = "atlas.lecture.bubbleOrigin"

    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    func show(capture: LectureCaptureModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = BubblePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RecordingBubbleView(capture: capture))
        panel.setFrameOrigin(savedOrigin())
        panel.orderFrontRegardless()

        // Remember where it was dragged to, so it returns there next lecture.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { notification in
            guard let moved = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                let origin = moved.frame.origin
                UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
            }
        }

        self.panel = panel
    }

    func hide() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    /// Defaults to the top-right of the active screen, clear of the menu bar.
    private func savedOrigin() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let fallback = NSPoint(
            x: screen.maxX - Self.size.width - 22,
            y: screen.maxY - Self.size.height - 14
        )

        guard let stored = UserDefaults.standard.string(forKey: Self.originKey) else { return fallback }
        let parts = stored.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return fallback }

        // A saved position on a monitor that is no longer attached would put
        // the bubble somewhere invisible.
        let candidate = NSPoint(x: parts[0], y: parts[1])
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(NSRect(origin: candidate, size: Self.size))
        }
        return isOnScreen ? candidate : fallback
    }
}

#endif
