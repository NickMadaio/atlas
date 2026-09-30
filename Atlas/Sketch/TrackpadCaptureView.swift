#if os(macOS)
import AppKit
import AtlasCore
import SwiftUI

/// Reads the trackpad as a tablet while writing mode is on.
///
/// Trackpad touches arrive as `NSTouch` with a `normalizedPosition` in 0…1 —
/// where the finger is on the glass, independent of the pointer. They are
/// delivered to the view under the pointer, so writing mode parks the pointer
/// over this view and detaches it from the trackpad
/// (`CGAssociateMouseAndMouseCursorPosition`) until writing mode ends.
/// Touching is pen down, lifting is pen up; no click is needed.
struct TrackpadCaptureView: NSViewRepresentable {
    @ObservedObject var model: TrackpadSketchModel

    func makeNSView(context: Context) -> TrackpadCaptureNSView {
        let view = TrackpadCaptureNSView()
        view.model = model
        return view
    }

    func updateNSView(_ view: TrackpadCaptureNSView, context: Context) {
        view.model = model
        view.setWriting(model.isWriting)
    }

    static func dismantleNSView(_ view: TrackpadCaptureNSView, coordinator: ()) {
        view.setWriting(false)
    }
}

final class TrackpadCaptureNSView: NSView {
    weak var model: TrackpadSketchModel?
    private var pen: (any NSCopying & NSObjectProtocol)?
    private var pointerLocked = false
    private var resignObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
        // A thumb resting on the glass is classed as resting and not delivered,
        // which is the only palm rejection this version has.
        wantsRestingTouches = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else {
            setWriting(false)
            return
        }
        // Switching apps must give the pointer back, or it stays frozen.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.isWriting = false }
        }
    }

    // MARK: - Writing mode

    func setWriting(_ writing: Bool) {
        guard writing != pointerLocked else { return }
        if writing {
            guard let window, window.isKeyWindow else {
                // Called from a SwiftUI update, so the reset has to wait a turn.
                DispatchQueue.main.async { [weak self] in self?.model?.isWriting = false }
                return
            }
            window.makeFirstResponder(self)
            parkPointer(in: window)
            CGAssociateMouseAndMouseCursorPosition(0)
            NSCursor.hide()
            pointerLocked = true
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            pointerLocked = false
            pen = nil
            model?.touchCancelled()
            model?.releaseAllKeys()
        }
    }

    /// Puts the pointer in the middle of this view so touches are routed here.
    private func parkPointer(in window: NSWindow) {
        let centerInWindow = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: centerInWindow)
        // Quartz display space has its origin at the top-left of the main display.
        let mainHeight = NSScreen.screens.first?.frame.height ?? onScreen.y
        CGWarpMouseCursorPosition(CGPoint(x: onScreen.x, y: mainHeight - onScreen.y))
    }

    // MARK: - Touches

    override func touchesBegan(with event: NSEvent) {
        guard pointerLocked, pen == nil,
              let touch = event.touches(matching: .began, in: self).first else { return }
        pen = touch.identity
        let size = touch.deviceSize
        let aspect = size.height > 0 ? Double(size.width / size.height) : nil
        model?.touchBegan(at: Self.point(touch), trackpadAspect: aspect)
    }

    override func touchesMoved(with event: NSEvent) {
        guard let touch = penTouch(in: event, phase: .moved) else { return }
        model?.touchMoved(to: Self.point(touch))
    }

    override func touchesEnded(with event: NSEvent) {
        guard let touch = penTouch(in: event, phase: .ended) else { return }
        model?.touchMoved(to: Self.point(touch))
        model?.touchEnded()
        pen = nil
    }

    override func touchesCancelled(with event: NSEvent) {
        guard penTouch(in: event, phase: .cancelled) != nil else { return }
        // A cancelled touch was still drawn by the finger; keep what it drew.
        model?.touchEnded()
        pen = nil
    }

    /// Only the first finger down is the pen; any others are ignored.
    private func penTouch(in event: NSEvent, phase: NSTouch.Phase) -> NSTouch? {
        guard pointerLocked, let pen else { return nil }
        return event.touches(matching: phase, in: self).first { $0.identity.isEqual(pen) }
    }

    private static func point(_ touch: NSTouch) -> SketchPoint {
        SketchPoint(x: Double(touch.normalizedPosition.x), y: Double(touch.normalizedPosition.y))
    }

    // Clicks while writing are the trackpad being pressed, not a request.
    override func mouseDown(with event: NSEvent) {
        if !pointerLocked { super.mouseDown(with: event) }
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        guard pointerLocked, let model else { return super.keyDown(with: event) }
        if event.keyCode == 53 { // Escape
            model.isWriting = false
            return
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased().first else {
            return super.keyDown(with: event)
        }
        if let pan = TrackpadSketchModel.PanKey(rawValue: key) {
            model.press(pan)
            return
        }
        switch key {
        case "e": model.zoom(in: true)
        case "q": model.zoom(in: false)
        case "]": model.adjustPenSize(by: 1)
        case "[": model.adjustPenSize(by: -1)
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.lowercased().first,
              let pan = TrackpadSketchModel.PanKey(rawValue: key) else {
            return super.keyUp(with: event)
        }
        model?.release(pan)
    }
}
#endif
