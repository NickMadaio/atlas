import CoreGraphics
import Testing
@testable import AtlasCore

@Suite("Window fitting")
struct WindowFitTests {
    /// The user's actual display, in points, minus the menu bar.
    private let visible = CGRect(x: 0, y: 0, width: 1_728, height: 1_083)
    private let minimum = CGSize(width: 1_120, height: 720)

    @Test("A window taller than the screen is brought back onto it")
    func oversizedWindowIsClamped() {
        // The frame Atlas actually had saved: 240 points below the bottom edge
        // and taller than the screen, so the bottom was cut off.
        let restored = CGRect(x: 482, y: -240, width: 1_423, height: 1_323)
        let fitted = WindowFrameFit.fitted(restored, in: visible, minimumSize: minimum)
        #expect(visible.contains(fitted))
    }

    @Test("A rescued window keeps an edge you can actually grab")
    func rescuedWindowsAreGrabbable() {
        let restored = CGRect(x: 482, y: -240, width: 1_423, height: 1_323)
        let fitted = WindowFrameFit.fitted(restored, in: visible, minimumSize: minimum)

        // Every edge inside the screen, by enough to put a pointer on.
        #expect(fitted.minY >= visible.minY + WindowFrameFit.rescueMargin)
        #expect(fitted.maxY <= visible.maxY - WindowFrameFit.rescueMargin)
        #expect(fitted.minX >= visible.minX + WindowFrameFit.rescueMargin)
        #expect(fitted.maxX <= visible.maxX - WindowFrameFit.rescueMargin)
    }

    @Test("A window spanning the whole height gets an edge back")
    func fullHeightWindowsAreInset() {
        // Technically on screen, and impossible to resize: the top edge is
        // under the menu bar and the bottom is at the screen's edge.
        let full = CGRect(x: 305, y: 0, width: 1_423, height: 1_083)
        let fitted = WindowFrameFit.fitted(full, in: visible, minimumSize: minimum)

        #expect(fitted != full)
        #expect(fitted.height < visible.height)
        #expect(fitted.minY >= visible.minY + WindowFrameFit.rescueMargin)
    }

    @Test("A window with room on every side is never touched")
    func comfortableWindowsAreLeftAlone() {
        let comfortable = CGRect(x: 120, y: 80, width: 1_400, height: 900)
        #expect(WindowFrameFit.fitted(comfortable, in: visible, minimumSize: minimum) == comfortable)
    }

    @Test("A window pushed off the right edge slides back")
    func offscreenWindowIsMoved() {
        let restored = CGRect(x: 1_600, y: 200, width: 1_200, height: 800)
        let fitted = WindowFrameFit.fitted(restored, in: visible, minimumSize: minimum)
        #expect(visible.contains(fitted))
        #expect(fitted.width == 1_200)
    }

    @Test("A window that already fits is left exactly as it is")
    func goodFrameIsUntouched() {
        let restored = CGRect(x: 120, y: 80, width: 1_400, height: 900)
        #expect(WindowFrameFit.fitted(restored, in: visible, minimumSize: minimum) == restored)
    }

    @Test("A window smaller than usable is grown, not just moved")
    func tinyWindowIsGrown() {
        let restored = CGRect(x: 40, y: 40, width: 500, height: 320)
        let fitted = WindowFrameFit.fitted(restored, in: visible, minimumSize: minimum)
        #expect(fitted.width >= 1_120)
        #expect(fitted.height >= 720)
        #expect(visible.contains(fitted))
    }

    @Test("On a screen smaller than the minimum, the screen wins")
    func smallScreenIsNotOverridden() {
        let small = CGRect(x: 0, y: 0, width: 900, height: 600)
        let fitted = WindowFrameFit.fitted(
            CGRect(x: 0, y: 0, width: 400, height: 300),
            in: small,
            minimumSize: minimum
        )
        // The screen wins over the requested minimum, and the rescue margin
        // still applies — a tiny screen is the case where being able to grab
        // the window matters most.
        #expect(small.contains(fitted))
        #expect(fitted.width < minimum.width)
        #expect(fitted.height < minimum.height)
        #expect(WindowFrameFit.minimum(minimum, in: small) == CGSize(width: 900, height: 600))
    }

    @Test("A screen with no size at all changes nothing")
    func degenerateScreenIsIgnored() {
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(WindowFrameFit.fitted(frame, in: .zero, minimumSize: minimum) == frame)
    }
}
