import SwiftUI

/// A native SwiftUI presentation of the six dimensions used by an evaluation.
///
/// The drawing itself is intentionally kept separate from the presentation
/// rows so the same, tested geometry is used for the grid, axes, and data
/// polygon. Labels remain regular SwiftUI text below the chart, which gives
/// Dynamic Type room to grow instead of placing text at fragile fixed points
/// around the hexagon.
struct ScoreRadarChart: View {
    let dimensions: [EvaluationDimensionRow]

    private var orderedDimensions: [EvaluationDimensionRow] {
        var values: [ScoreDimension: EvaluationDimensionRow] = [:]
        for row in dimensions {
            values[row.dimension] = row
        }
        return ScoreDimension.allCases.map { dimension in
            values[dimension] ?? EvaluationDimensionRow(
                dimension: dimension,
                score: 0,
                feedback: "暂无该维度的文字反馈。"
            )
        }
    }

    private var accessibilitySummary: String {
        orderedDimensions.map { row in
            "\(label(for: row)) \(row.score) 分"
        }
        .joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("六维评分")
                .font(.headline)

            RadarCanvas(dimensions: orderedDimensions)
                .frame(height: 280)

            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(orderedDimensions, id: \.dimension.rawValue) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(label(for: row))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 2)
                        Text("\(row.score)")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("六维评分雷达图")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("依次显示正确性、覆盖度、推理深度、表达结构、权衡意识和术语精确性")
        .accessibilityIdentifier(PracticeAccessibilityID.radar)
    }

    private func label(for row: EvaluationDimensionRow) -> String {
        guard let index = ScoreDimension.allCases.firstIndex(of: row.dimension),
              index < RadarChartLayout.dimensionLabels.count else {
            return row.dimension.displayName
        }
        return RadarChartLayout.dimensionLabels[index]
    }
}

private struct RadarCanvas: View {
    let dimensions: [EvaluationDimensionRow]

    private let gridLevels = 5

    var body: some View {
        GeometryReader { proxy in
            let side = max(0, min(proxy.size.width, proxy.size.height))
            let chartSize = CGSize(width: side, height: side)
            let scores = dimensions.map { $0.score }
            let maxScores = Array(repeating: 100, count: RadarChartLayout.dimensionCount)
            let grid = RadarChartLayout.gridPoints(levels: gridLevels, size: chartSize)
            let axes = RadarChartLayout.axisSegments(size: chartSize)
            let polygon = RadarChartLayout.closedPolygon(
                scores: scores,
                maxScores: maxScores,
                size: chartSize
            )

            Canvas { context, _ in
                for points in grid {
                    context.stroke(
                        closedPath(points),
                        with: .color(.secondary.opacity(0.24)),
                        lineWidth: 1
                    )
                }

                for segment in axes {
                    var path = Path()
                    path.move(to: segment.start)
                    path.addLine(to: segment.end)
                    context.stroke(
                        path,
                        with: .color(.secondary.opacity(0.32)),
                        lineWidth: 1
                    )
                }

                guard polygon.count > 1 else { return }
                let dataPath = closedPath(polygon)
                context.fill(dataPath, with: .color(Color.accentColor.opacity(0.22)))
                context.stroke(
                    dataPath,
                    with: .color(Color.accentColor),
                    lineWidth: 2.5
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
