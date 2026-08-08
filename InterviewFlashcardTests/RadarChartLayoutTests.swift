import CoreGraphics
import XCTest

final class RadarChartLayoutTests: XCTestCase {
    func testPointsFollowTheFixedSixDimensionOrder() {
        XCTAssertEqual(RadarChartLayout.dimensionCount, ScoreDimension.allCases.count)
        XCTAssertEqual(
            RadarChartLayout.dimensionLabels,
            ["正确性", "覆盖度", "推理深度", "表达结构", "权衡意识", "术语精确性"]
        )
    }

    func testZeroScoresMeetAtTheCenterAndFullScoresReachOuterVertices() {
        let size = CGSize(width: 240, height: 240)
        let center = CGPoint(x: 120, y: 120)
        let zero = RadarChartLayout.points(
            scores: [0, 0, 0, 0, 0, 0],
            maxScores: [100, 100, 100, 100, 100, 100],
            size: size
        )
        let full = RadarChartLayout.points(
            scores: [100, 100, 100, 100, 100, 100],
            maxScores: [100, 100, 100, 100, 100, 100],
            size: size
        )

        XCTAssertEqual(zero, Array(repeating: center, count: 6))
        XCTAssertEqual(full[0].x, center.x, accuracy: 0.0001)
        XCTAssertEqual(full[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(full[3].x, center.x, accuracy: 0.0001)
        XCTAssertEqual(full[3].y, size.height, accuracy: 0.0001)
        XCTAssertEqual(full.count, 6)
    }

    func testScoresAreClampedAndMissingDimensionsBecomeCenterPoints() {
        let points = RadarChartLayout.points(
            scores: [120, -20, 40],
            maxScores: [100, 100, 0],
            size: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(points.count, 6)
        XCTAssertEqual(points[1].x, 100, accuracy: 0.0001)
        XCTAssertEqual(points[1].y, 50, accuracy: 0.0001)
        XCTAssertFalse(points.contains { $0.x.isNaN || $0.y.isNaN })
    }

    func testGridAndAxesHaveExpectedGeometryWithoutNaNForZeroSize() {
        let grid = RadarChartLayout.gridPoints(levels: 5, size: CGSize(width: 180, height: 120))
        let axes = RadarChartLayout.axisSegments(size: CGSize(width: 180, height: 120))
        XCTAssertEqual(grid.count, 5)
        XCTAssertTrue(grid.allSatisfy { $0.count == 6 })
        XCTAssertEqual(axes.count, 6)
        XCTAssertTrue(axes.allSatisfy { segment in
            !segment.start.x.isNaN && !segment.start.y.isNaN
                && !segment.end.x.isNaN && !segment.end.y.isNaN
        })

        let zeroGrid = RadarChartLayout.gridPoints(levels: 5, size: .zero)
        let zeroAxes = RadarChartLayout.axisSegments(size: .zero)
        XCTAssertTrue(zeroGrid.flatMap { $0 }.allSatisfy { $0 == .zero })
        XCTAssertTrue(zeroAxes.allSatisfy { $0.start == .zero && $0.end == .zero })
    }

    func testGridLevelsAreClampedToAtLeastOneAndDataPolygonIsClosed() {
        let grid = RadarChartLayout.gridPoints(levels: 0, size: CGSize(width: 100, height: 100))
        XCTAssertEqual(grid.count, 1)

        let polygon = RadarChartLayout.closedPolygon(
            scores: [50, 50, 50, 50, 50, 50],
            maxScores: [100, 100, 100, 100, 100, 100],
            size: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(polygon.first, polygon.last)
        XCTAssertEqual(polygon.count, 7)
    }
}
