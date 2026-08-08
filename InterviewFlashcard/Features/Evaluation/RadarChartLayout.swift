import CoreGraphics
import Foundation

/// Pure geometry for the six-dimension score radar.
///
/// The layout deliberately knows nothing about SwiftUI. Scores are normalized
/// against their per-axis maxima, clamped to the chart domain, and mapped to a
/// clockwise hexagon whose first axis starts at twelve o'clock.
enum RadarChartLayout {
    static let dimensionLabels = [
        "正确性",
        "覆盖度",
        "推理深度",
        "表达结构",
        "权衡意识",
        "术语精确性"
    ]

    static var dimensionCount: Int { dimensionLabels.count }

    struct Segment: Equatable, Sendable {
        let start: CGPoint
        let end: CGPoint
    }

    static func points(
        scores: [Double],
        maxScores: [Double],
        size: CGSize
    ) -> [CGPoint] {
        let normalized = normalizedScores(scores: scores, maxScores: maxScores)
        return normalized.enumerated().map { index, value in
            point(fraction: value, index: index, size: size)
        }
    }

    static func points(
        scores: [Int],
        maxScores: [Int],
        size: CGSize
    ) -> [CGPoint] {
        points(
            scores: scores.map(Double.init),
            maxScores: maxScores.map(Double.init),
            size: size
        )
    }

    static func normalizedScores(scores: [Double], maxScores: [Double]) -> [Double] {
        (0..<dimensionCount).map { index in
            guard index < scores.count, index < maxScores.count else { return 0 }
            let score = scores[index]
            let maximum = maxScores[index]
            guard score.isFinite, maximum.isFinite, maximum > 0 else { return 0 }
            return min(max(score / maximum, 0), 1)
        }
    }

    static func gridPoints(levels: Int = 5, size: CGSize) -> [[CGPoint]] {
        let levelCount = max(levels, 1)
        return (1...levelCount).map { level in
            let fraction = Double(level) / Double(levelCount)
            return (0..<dimensionCount).map { index in
                point(fraction: fraction, index: index, size: size)
            }
        }
    }

    static func axisSegments(size: CGSize) -> [Segment] {
        let center = chartCenter(for: size)
        return points(
            scores: Array(repeating: 1, count: dimensionCount),
            maxScores: Array(repeating: 1, count: dimensionCount),
            size: size
        ).map { Segment(start: center, end: $0) }
    }

    static func closedPolygon(
        scores: [Double],
        maxScores: [Double],
        size: CGSize
    ) -> [CGPoint] {
        let values = points(scores: scores, maxScores: maxScores, size: size)
        guard let first = values.first else { return [] }
        return values + [first]
    }

    static func closedPolygon(
        scores: [Int],
        maxScores: [Int],
        size: CGSize
    ) -> [CGPoint] {
        closedPolygon(
            scores: scores.map(Double.init),
            maxScores: maxScores.map(Double.init),
            size: size
        )
    }

    private static func point(fraction: Double, index: Int, size: CGSize) -> CGPoint {
        let center = chartCenter(for: size)
        let radius = max(0, min(max(size.width, 0), max(size.height, 0)) / 2)
        let angle = -Double.pi / 2 + (Double(index) * 2 * Double.pi / Double(dimensionCount))
        return CGPoint(
            x: center.x + CGFloat(min(max(fraction, 0), 1) * cos(angle)) * radius,
            y: center.y + CGFloat(min(max(fraction, 0), 1) * sin(angle)) * radius
        )
    }

    private static func chartCenter(for size: CGSize) -> CGPoint {
        CGPoint(
            x: max(size.width, 0) / 2,
            y: max(size.height, 0) / 2
        )
    }
}
