import AtlasCore
import SwiftUI

/// Draws the page through a camera that follows the trackpad frame.
///
/// The frame always fills the same share of the window, so the writing under
/// your finger is a steady size on screen. Zooming in therefore enlarges what
/// is already on the page, and new writing is smaller than it by comparison.
struct SketchCamera {
    /// How much page shows around the frame: 1.35 = frame fills ~74% of the view.
    static let margin = 1.35

    let scale: Double
    let focus: SketchPoint
    let viewCenter: CGPoint

    init(viewport: SketchViewport, viewSize: CGSize) {
        let fitsWidth = Double(viewSize.width) / (viewport.width * Self.margin)
        let fitsHeight = Double(viewSize.height) / (viewport.height * Self.margin)
        scale = max(min(fitsWidth, fitsHeight), 0.0001)
        focus = viewport.center
        viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    func view(_ point: SketchPoint) -> CGPoint {
        CGPoint(
            x: viewCenter.x + CGFloat((point.x - focus.x) * scale),
            y: viewCenter.y + CGFloat((point.y - focus.y) * scale)
        )
    }

    func view(_ rect: SketchRect) -> CGRect {
        let origin = view(SketchPoint(x: rect.minX, y: rect.minY))
        return CGRect(x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
    }
}

enum SketchCanvasRenderer {
    /// Ruled-line spacing in page units.
    static let ruleSpacing = 90.0

    static func strokePath(_ stroke: SketchStroke, map: (SketchPoint) -> CGPoint) -> Path {
        Path { path in
            guard let first = stroke.points.first else { return }
            path.move(to: map(first))
            if stroke.points.count == 1 {
                // A tap is a dot: a zero-length line with round caps.
                path.addLine(to: map(first))
            } else {
                stroke.points.dropFirst().forEach { path.addLine(to: map($0)) }
            }
        }
    }

    static func drawStroke(_ stroke: SketchStroke, in context: GraphicsContext, scale: Double, color: Color, map: (SketchPoint) -> CGPoint) {
        context.stroke(
            strokePath(stroke, map: map),
            with: .color(color),
            style: StrokeStyle(lineWidth: max(stroke.width * scale, 0.5), lineCap: .round, lineJoin: .round)
        )
    }

    static func drawRules(page: SketchSize, camera: SketchCamera, in context: GraphicsContext, viewSize: CGSize, color: Color) {
        let spacingOnScreen = ruleSpacing * camera.scale
        guard spacingOnScreen >= 8 else { return }
        let left = camera.view(SketchPoint(x: 0, y: 0)).x
        let right = camera.view(SketchPoint(x: page.width, y: 0)).x
        let topVisible = max(0, camera.focus.y - Double(viewSize.height) / 2 / camera.scale)
        let bottomVisible = min(page.height, camera.focus.y + Double(viewSize.height) / 2 / camera.scale)
        let firstRule = (topVisible / ruleSpacing).rounded(.up) * ruleSpacing
        let rules = Path { path in
            stride(from: firstRule, through: bottomVisible, by: ruleSpacing).forEach { y in
                let screenY = camera.view(SketchPoint(x: 0, y: y)).y
                path.move(to: CGPoint(x: left, y: screenY))
                path.addLine(to: CGPoint(x: right, y: screenY))
            }
        }
        context.stroke(rules, with: .color(color), lineWidth: 1)
    }
}
