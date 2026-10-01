import CoreGraphics

/// Keeps a window inside the screen it is on.
///
/// macOS restores the frame a window last had without checking that it still
/// fits, e.g. a frame saved on a larger display. The result can hang off the
/// screen with the title bar and resize handles out of reach.
///
/// Pure arithmetic, kept apart from the AppKit plumbing so the clamping can be
/// checked without a window.
public enum WindowFrameFit {
    /// How much screen a rescued window is left on each side. A window clamped
    /// to exactly the visible frame has its edges flush with the screen's, so
    /// there is no resize handle to grab.
    public static let rescueMargin: CGFloat = 16

    /// The frame a window should have: at least `minimumSize`, never larger
    /// than the visible area, and fully inside it.
    ///
    /// Size is settled before position, because moving a window that is too
    /// big only trades one cut-off edge for another.
    public static func fitted(
        _ frame: CGRect,
        in visible: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        guard visible.width > 0, visible.height > 0 else { return frame }

        // A minimum wider than the screen is not a minimum. The screen wins.
        let floor = minimum(minimumSize, in: visible)

        // Left alone when it is on screen, big enough, and not spanning a whole
        // axis (a window touching both edges has no handle to drag on that side).
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
