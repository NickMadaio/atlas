import Foundation

public struct SketchPoint: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: SketchPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

public struct SketchSize: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct SketchRect: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
}

/// The part of the page the trackpad is laid over.
///
/// The mapping is absolute: a finger's position on the trackpad, as a fraction
/// of its width and height, is the pen's position as the same fraction of this
/// frame. Panning moves the frame across the page and zooming changes how much
/// page it covers, but neither changes the mapping itself — which is why
/// writing done while zoomed in is smaller on the page than writing done before.
///
/// Page coordinates run with y downward, like the screen.
public struct SketchViewport: Codable, Equatable, Sendable {
    /// Below this the frame is so small that finger noise dominates the line.
    public static let minimumWidth: Double = 120

    public let pageSize: SketchSize
    public let center: SketchPoint
    /// Frame width in page units. Height follows from `aspect`.
    public let width: Double
    /// The trackpad's width divided by its height.
    public let aspect: Double

    public init(pageSize: SketchSize, center: SketchPoint, width: Double, aspect: Double) {
        let safeAspect = aspect.isFinite && aspect > 0 ? aspect : 1.6
        let widestAllowed = min(pageSize.width, pageSize.height * safeAspect)
        let fittedWidth = min(max(width, Self.minimumWidth), widestAllowed)
        let halfWidth = fittedWidth / 2
        let halfHeight = fittedWidth / safeAspect / 2
        self.pageSize = pageSize
        self.width = fittedWidth
        self.aspect = safeAspect
        self.center = SketchPoint(
            x: min(max(center.x, halfWidth), pageSize.width - halfWidth),
            y: min(max(center.y, halfHeight), pageSize.height - halfHeight)
        )
    }

    public var height: Double { width / aspect }

    public var rect: SketchRect {
        SketchRect(minX: center.x - width / 2, minY: center.y - height / 2, width: width, height: height)
    }

    /// Maps a trackpad position — `NSTouch.normalizedPosition`, 0…1 on both
    /// axes with y measured from the *bottom* — to a point on the page.
    public func pagePoint(forTouchAt normalized: SketchPoint) -> SketchPoint {
        let x = min(max(normalized.x, 0), 1)
        let yFromTop = 1 - min(max(normalized.y, 0), 1)
        let frame = rect
        return SketchPoint(x: frame.minX + x * frame.width, y: frame.minY + yFromTop * frame.height)
    }

    public func panned(dx: Double, dy: Double) -> SketchViewport {
        SketchViewport(
            pageSize: pageSize,
            center: SketchPoint(x: center.x + dx, y: center.y + dy),
            width: width,
            aspect: aspect
        )
    }

    /// `factor` above 1 zooms in: the frame covers less page.
    public func zoomed(by factor: Double) -> SketchViewport {
        guard factor.isFinite, factor > 0 else { return self }
        return SketchViewport(pageSize: pageSize, center: center, width: width / factor, aspect: aspect)
    }

    public func withAspect(_ newAspect: Double) -> SketchViewport {
        SketchViewport(pageSize: pageSize, center: center, width: width, aspect: newAspect)
    }

    /// The pen size is chosen in trackpad terms, so a line looks the same
    /// weight under your finger at any zoom and scales with the writing.
    public func pageLineWidth(forPenSize penSize: Double) -> Double {
        penSize * width / SketchDocument.referenceViewportWidth
    }
}
