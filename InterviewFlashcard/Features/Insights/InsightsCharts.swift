import Charts
import SwiftUI
import UIKit

struct InsightsChartCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let accessibilityID: String
    let accessibilityLabel: String
    let accessibilityValue: String
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        accessibilityID: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessibilityID = accessibilityID
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }
}

struct InsightsCoverageChart: View {
    let snapshot: InsightsAggregator.Snapshot

    private var segments: [InsightsChartData.CoverageSegment] {
        InsightsChartData.coverageSegments(from: snapshot)
    }

    var body: some View {
        if segments.isEmpty {
            InsightsEmptyChartState(text: "添加题目后会显示练习覆盖率。")
        } else {
            VStack(spacing: 12) {
                ZStack {
                    Chart(segments) { segment in
                        SectorMark(
                            angle: .value("题目数", segment.value),
                            innerRadius: .ratio(0.68),
                            angularInset: 2
                        )
                        .foregroundStyle(color(for: segment.kind))
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)

                    VStack(spacing: 2) {
                        Text("\(Int((snapshot.coverageRate * 100).rounded()))%")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                        Text("已练习")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 190)

                HStack(spacing: 16) {
                    legend(.practiced, value: snapshot.practicedCards)
                    legend(.unpracticed, value: snapshot.unpracticedCards)
                }
                .font(.caption)
            }
        }
    }

    private func legend(_ kind: InsightsChartData.CoverageKind, value: Int) -> some View {
        Label("\(kind.displayName) \(value)", systemImage: "circle.fill")
            .foregroundStyle(kind == .practiced ? Color.accentColor : Color.secondary)
    }

    private func color(for kind: InsightsChartData.CoverageKind) -> Color {
        kind == .practiced ? .accentColor : .secondary.opacity(0.28)
    }
}

struct InsightsScoreChart: View {
    let snapshot: InsightsAggregator.Snapshot

    private var metrics: [InsightsChartData.ScoreMetric] {
        InsightsChartData.scoreMetrics(from: snapshot)
    }

    var body: some View {
        if metrics.isEmpty {
            InsightsEmptyChartState(text: "完成一次评分后会显示分数对比。")
        } else {
            Chart(metrics) { metric in
                BarMark(
                    x: .value("项目", metric.label),
                    y: .value("分数", metric.value)
                )
                .foregroundStyle(color(for: metric.kind))
                .annotation(position: .top, alignment: .center) {
                    Text("\(metric.value)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) {
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks { AxisValueLabel() }
            }
            .frame(height: 220)
        }
    }

    private func color(for kind: InsightsChartData.ScoreKind) -> Color {
        switch kind {
        case .average: .accentColor
        case .latest: .orange
        case .best: .green
        }
    }
}

struct InsightsActivityChart: View {
    let snapshot: InsightsAggregator.Snapshot

    var body: some View {
        InsightsActivityHeatmap(
            snapshot: snapshot,
            asOf: Date(),
            calendar: Self.calendar
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

struct InsightsDimensionsChart: View {
    let snapshot: InsightsAggregator.Snapshot

    var body: some View {
        InsightsRadarChart(snapshot: snapshot)
    }
}

struct InsightsTopicsChart: View {
    let snapshot: InsightsAggregator.Snapshot
    let selectedTopicID: UUID?

    var body: some View {
        InsightsTopicProgressList(snapshot: snapshot, selectedTopicID: selectedTopicID)
    }
}

struct InsightsTrendChart: View {
    let snapshot: InsightsAggregator.Snapshot

    private var points: [InsightsChartData.TrendMetric] {
        InsightsChartData.trendMetrics(from: snapshot)
    }

    private var scoredPoints: [InsightsChartData.TrendMetric] {
        points.filter { $0.averageScore != nil }
    }

    var body: some View {
        if points.isEmpty {
            InsightsEmptyChartState(text: "完成一次回答后会显示趋势。")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("平均分趋势")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if scoredPoints.isEmpty {
                    Text("趋势中还没有已评分回答。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    scoreTrend
                }

                Text("每日回答次数")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                answerTrend
            }
        }
    }

    private var scoreTrend: some View {
        Chart(scoredPoints) { point in
            AreaMark(
                x: .value("日期", point.date),
                y: .value("平均分", point.averageScore ?? 0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [InsightsDashboardPalette.purple.opacity(0.35), InsightsDashboardPalette.purple.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("日期", point.date),
                y: .value("平均分", point.averageScore ?? 0)
            )
            .foregroundStyle(InsightsDashboardPalette.purple)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("日期", point.date),
                y: .value("平均分", point.averageScore ?? 0)
            )
            .foregroundStyle(InsightsDashboardPalette.purple)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 190)
    }

    private var answerTrend: some View {
        Chart(points) { point in
            BarMark(
                x: .value("日期", point.date),
                y: .value("回答次数", point.answerCount)
            )
            .foregroundStyle(InsightsDashboardPalette.cyan)
            .annotation(position: .top, alignment: .center) {
                Text("\(point.answerCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { AxisGridLine(); AxisValueLabel() }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 170)
    }
}

struct InsightsEmptyChartState: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "chart.bar.xaxis")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            .multilineTextAlignment(.center)
    }
}
