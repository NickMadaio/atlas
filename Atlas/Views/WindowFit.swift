import AtlasCore
import SwiftUI

#if os(macOS)
import AppKit

/// Applies `WindowFrameFit` to the window this view lands in.
///
/// Attached as a zero-size background rather than a scene modifier, because the
/// frame has to be corrected on the real `NSWindow` after macOS has restored
/// it — a `.defaultSize` is only consulted when there is nothing to restore,
/// which is exactly the case where nothing was wrong.
struct AtlasWindowFit: NSViewRepresentable {
    var minimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.watch(view) { apply(to: view) }
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(to: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// A SwiftUI update is not the only way a window ends up off screen.
    ///
    /// Dragging it mostly off the right edge, or unplugging the display it was
    /// sized for, changes nothing SwiftUI knows about — so clamping only when
    /// the view hierarchy updates leaves the window broken until something else
    /// happens to redraw. These are the three notifications that actually fire.
    final class Coordinator {
        private var tokens: [NSObjectProtocol] = []

        func watch(_ view: NSView, refit: @escaping () -> Void) {
            let center = NotificationCenter.default
            // didResize, NOT didEndLiveResize: the latter fires only when a
            // person finishes dragging an edge. The resize that actually broke
            // this window was AppKit restoring a saved frame, which is
            // programmatic and fires only didResize.
            for name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSApplication.didChangeScreenParametersNotification
            ] {
                tokens.append(
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak view] notification in
                        // Only this view's own window; every window in the app
                        // posts these.
                        if let window = notification.object as? NSWindow,
                           window !== view?.window {
                            return
                        }
                        refit()
                    }
                )
            }
        }

        deinit {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
        }
    }

    private func apply(to view: NSView) {
        // The window is not attached during the first layout pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Never fight someone who is dragging the edge right now.
            guard !window.inLiveResize else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }

            let visible = screen.visibleFrame
            window.minSize = WindowFrameFit.minimum(minimumSize, in: visible)
            // Worth setting, but NOT the guarantee it looks like: minSize and
            // maxSize constrain dragging an edge and nothing else. A
            // programmatic setFrame — which is what SwiftUI does — goes
            // straight past them. The window not resizing itself is handled by
            // .windowResizability(.contentMinSize) on the scene; this is the
            // net for a window that arrives on a screen it no longer fits.
            window.maxSize = visible.size

            let fitted = WindowFrameFit.fitted(window.frame, in: visible, minimumSize: minimumSize)
            guard fitted != window.frame else { return }
            window.setFrame(fitted, display: true)
        }
    }
}

extension View {
    /// Keeps the window holding this view on screen and usably large.
    func atlasFitsItsWindow(minimumWidth: CGFloat, minimumHeight: CGFloat) -> some View {
        background(
            AtlasWindowFit(minimumSize: CGSize(width: minimumWidth, height: minimumHeight))
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
#endif
