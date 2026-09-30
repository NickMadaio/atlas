import CoreGraphics

/// Keeps a window inside the screen it is on.
///
/// macOS restores the frame a window last had, and it does not check that the
/// frame still fits. Atlas's own saved frame was 1728×1146 on a display with
/// 1083 points of usable height: taller than the screen, positioned 63 points
/// below the bottom, so the title bar sat above the top edge and the foot of
/// every layout was cut off. From inside the app that is unfixable, because the
/// controls you would use to fix it are the ones off screen.
///
/// Pure arithmetic, kept apart from the AppKit plumbing so the clamping can be
/// checked without a window.
public enum WindowFrameFit {
    /// The frame a window should have: at least `minimumSize`, never larger
    /// than the visible area, and fully inside it.
    ///
    /// The order matters. Size is settled first and position second, because
    /// moving a window that is too big only trades one cut-off edge for
    /// another.
    /// How much screen a rescued window is left on each side.
    ///
    /// A window corrected to exactly the visible frame is technically on screen
    /// and still unusable: its edges sit flush with the screen's, so there is
    /// no resize handle to grab and no way out of the size it is stuck at. That
    /// was the actual complaint — "the bottom is cut off and I can't resize
    /// it" — and clamping to the full visible frame does not fix it.
    public static let rescueMargin: CGFloat = 16

    public static func fitted(
        _ frame: CGRect,
        in visible: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        guard visible.width > 0, visible.height > 0 else { return frame }

        // A minimum wider than the screen is not a minimum. The screen wins.
        let floor = minimum(minimumSize, in: visible)

        // Left exactly as it is when it is inside the screen, big enough to
        // use, and not spanning an entire axis. That last one matters: a
        // window touching both edges of an axis has no handle to drag on that
        // side, which is indistinguishable from being stuck — "the bottom is
        // cut off and I can't resize it" describes a window ending exactly at
        // the screen's edge just as well as one hanging past it.
        let spansAnAxis = frame.width >= visible.width || frame.height >= visible.height
        let bigEnough = frame.width >= floor.width && frame.height >= floor.height
        if visible.contains(frame), !spansAnAxis, bigEnough {
            return frame
        }

        // Anything being rescued is brought inside a margin, so it always comes
        // back with an edge that can be grabbed.
        let room = visible.insetBy(dx: rescueMargin, dy: rescueMargin)
        let bounds = room.width > 0 && room.height > 0 ? room : visible
        let bounded = minimum(minimumSize, in: bounds)

        let size = CGSize(
            width: min(max(frame.width, bounded.width), bounds.width),
            height: min(max(frame.height, bounded.height), bounds.height)
        )
        let origin = CGPoint(
            x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
            y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    /// The size a window may not shrink below, once the screen has had its say.
    public static func minimum(_ minimumSize: CGSize, in visible: CGRect) -> CGSize {
        guard visible.width > 0, visible.height > 0 else { return minimumSize }
        return CGSize(
            width: min(minimumSize.width, visible.width),
            height: min(minimumSize.height, visible.height)
        )
    }
}
