import Foundation

public struct SketchStroke: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Line width in page units.
    public let width: Double
    public let points: [SketchPoint]

    public init(id: UUID = UUID(), width: Double, points: [SketchPoint]) {
        self.id = id
        self.width = width
        self.points = points
    }

    public func appending(_ point: SketchPoint) -> SketchStroke {
        SketchStroke(id: id, width: width, points: points + [point])
    }

    /// The same stroke with its samples replaced by a smooth curve through them.
    public func smoothed(stepsPerSegment: Int = 6) -> SketchStroke {
        SketchStroke(id: id, width: width, points: SketchCurve.interpolated(points, stepsPerSegment: stepsPerSegment))
    }
}

public struct SketchPage: Codable, Equatable, Sendable {
    public let size: SketchSize
    public let strokes: [SketchStroke]

    public init(size: SketchSize, strokes: [SketchStroke] = []) {
        self.size = size
        self.strokes = strokes
    }

    public func adding(_ stroke: SketchStroke) -> SketchPage {
        SketchPage(size: size, strokes: strokes + [stroke])
    }

    public func removingLastStroke() -> SketchPage {
        SketchPage(size: size, strokes: Array(strokes.dropLast()))
    }

    public func cleared() -> SketchPage {
        SketchPage(size: size)
    }
}

/// Cleans raw trackpad samples before they become a line.
///
/// Trackpad positions wobble by a fraction of a millimetre even under a still
/// finger. Samples closer than `minimumDistance` to the last accepted one are
/// dropped, and each accepted sample is eased toward the previous one by
/// `smoothing` (0 = raw, toward 1 = heavily damped).
public struct SketchInputFilter: Sendable {
    public let smoothing: Double
    public let minimumDistance: Double
    private var last: SketchPoint?

    public init(smoothing: Double = 0.35, minimumDistance: Double = 1.5) {
        self.smoothing = min(max(smoothing, 0), 0.95)
        self.minimumDistance = max(minimumDistance, 0)
    }

    /// Returns the point to add to the stroke, or nil if the sample is jitter.
    public mutating func accept(_ raw: SketchPoint) -> SketchPoint? {
        guard let previous = last else {
            last = raw
            return raw
        }
        guard previous.distance(to: raw) >= minimumDistance else { return nil }
        let eased = SketchPoint(
            x: previous.x + (raw.x - previous.x) * (1 - smoothing),
            y: previous.y + (raw.y - previous.y) * (1 - smoothing)
        )
        last = eased
        return eased
    }
}

/// Catmull-Rom interpolation: a curve that passes through every sample, so
/// handwriting keeps its shape but loses the corners between samples.
public enum SketchCurve {
    public static func interpolated(_ samples: [SketchPoint], stepsPerSegment: Int) -> [SketchPoint] {
        guard samples.count > 1, stepsPerSegment > 1 else { return samples }
        let lastIndex = samples.count - 1
        let segments = (0..<lastIndex).flatMap { index -> [SketchPoint] in
            let p0 = samples[max(index - 1, 0)]
            let p1 = samples[index]
            let p2 = samples[index + 1]
            let p3 = samples[min(index + 2, lastIndex)]
            return (0..<stepsPerSegment).map { step in
                point(p0, p1, p2, p3, t: Double(step) / Double(stepsPerSegment))
            }
        }
        return segments + [samples[lastIndex]]
    }

    private static func point(_ p0: SketchPoint, _ p1: SketchPoint, _ p2: SketchPoint, _ p3: SketchPoint, t: Double) -> SketchPoint {
        guard t > 0 else { return p1 }
        let t2 = t * t
        let t3 = t2 * t
        func axis(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return SketchPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
    }
}
