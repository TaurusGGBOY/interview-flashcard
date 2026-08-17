import SwiftUI
import UIKit

enum InsightsDashboardPalette {
    static let blue = Color(red: 0.16, green: 0.42, blue: 0.96)
    static let cyan = Color(red: 0.19, green: 0.72, blue: 0.93)
    static let green = Color(red: 0.18, green: 0.72, blue: 0.49)
    static let orange = Color(red: 0.98, green: 0.52, blue: 0.22)
    static let pink = Color(red: 0.91, green: 0.31, blue: 0.57)
    static let purple = Color(red: 0.47, green: 0.31, blue: 0.88)

    static let heroGradient = LinearGradient(
        colors: [blue, purple, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct InsightsOverviewCard: View {
    let snapshot: InsightsAggregator.Snapshot
    let scopeName: String

    private var coverageProgress: Double {
        min(max(snapshot.coverageRate, 0), 1)
    }

    private var scoreProgress: Double {
        snapshot.scoredAnswerCount == 0
            ? 0
            : min(max(Double(snapshot.averageScore) / 100, 0), 1)
    }

    private var consistencyProgress: Double {
        min(Double(snapshot.practiceDays) / 30, 1)
    }

    private var scoreText: String {
        snapshot.scoredAnswerCount == 0 ? "—" : "\(snapshot.averageScore)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("学习状态")
                        .font(.title3.weight(.bold))
                    Label(scopeName, systemImage: "scope")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: 8)

                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(10)
                    .background(.white.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                InsightsMetricRing(
                    title: "覆盖率",
                    value: "\(Int((snapshot.coverageRate * 100).rounded()))%",
                    progress: coverageProgress,
                    color: InsightsDashboardPalette.cyan
                )
                InsightsMetricRing(
                    title: "平均分",
                    value: scoreText,
                    progress: scoreProgress,
                    color: InsightsDashboardPalette.orange
                )
                InsightsMetricRing(
                    title: "练习天数",
                    value: "\(snapshot.practiceDays)",
                    progress: consistencyProgress,
                    color: InsightsDashboardPalette.green
                )
            }

            HStack(spacing: 0) {
                overviewStat(title: "题目", value: "\(snapshot.totalCards)")
                overviewStat(title: "回答", value: "\(snapshot.answerCount)")
                overviewStat(title: "近 7 日", value: "\(snapshot.sevenDayAnswerCount)")
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(.white)
        .background(InsightsDashboardPalette.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 150, height: 150)
                .offset(x: 46, y: -66)
                .blur(radius: 2)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: InsightsDashboardPalette.purple.opacity(0.22), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(InsightsAccessibilityID.metrics)
        .accessibilityLabel("学习状态，\(scopeName)")
        .accessibilityValue(
            "覆盖率 \(Int((snapshot.coverageRate * 100).rounded()))%，平均分 \(scoreText)，练习 \(snapshot.practiceDays) 天，题目 \(snapshot.totalCards) 个，回答 \(snapshot.answerCount) 次，近 7 日 \(snapshot.sevenDayAnswerCount) 次"
        )
    }

    private func overviewStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InsightsMetricRing: View {
    let title: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 68, height: 68)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity)
    }
}

struct InsightsRadarChart: View {
    let snapshot: InsightsAggregator.Snapshot

    private var metrics: [InsightsChartData.DimensionMetric] {
        InsightsChartData.dimensionMetrics(from: snapshot)
    }

    var body: some View {
        if metrics.isEmpty {
            InsightsEmptyChartState(text: "完成一次评分后会显示六维能力。")
        } else {
            VStack(spacing: 14) {
                GeometryReader { proxy in
                    let side = max(0, min(proxy.size.width, proxy.size.height))
                    let size = CGSize(width: side, height: side)
                    let scores = metrics.map(\.value)
                    let maxScores = Array(repeating: 100, count: RadarChartLayout.dimensionCount)
                    let grid = RadarChartLayout.gridPoints(levels: 5, size: size)
                    let axes = RadarChartLayout.axisSegments(size: size)
                    let polygon = RadarChartLayout.closedPolygon(
                        scores: scores,
                        maxScores: maxScores,
                        size: size
                    )

                    Canvas { context, _ in
                        for points in grid {
                            context.stroke(
                                closedPath(points),
                                with: .color(.secondary.opacity(0.22)),
                                lineWidth: 1
                            )
                        }

                        for axis in axes {
                            var path = Path()
                            path.move(to: axis.start)
                            path.addLine(to: axis.end)
                            context.stroke(
                                path,
                                with: .color(.secondary.opacity(0.28)),
                                lineWidth: 1
                            )
                        }

                        let dataPath = closedPath(polygon)
                        context.fill(dataPath, with: .color(InsightsDashboardPalette.purple.opacity(0.22)))
                        context.stroke(
                            dataPath,
                            with: .color(InsightsDashboardPalette.purple),
                            style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)
                        )
                    }
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 220)

                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(metrics) { metric in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(InsightsDashboardPalette.purple)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(metric.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 2)
                            Text("\(metric.value)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("六维能力雷达图")
            .accessibilityValue(metrics.map { "\($0.label) \($0.value) 分" }.joined(separator: "，"))
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

struct InsightsActivityHeatmap: View {
    let snapshot: InsightsAggregator.Snapshot
    let asOf: Date
    let calendar: Calendar

    private var metrics: [InsightsChartData.DailyActivityMetric] {
        InsightsChartData.activityHeatmapMetrics(
            from: snapshot,
            asOf: asOf,
            calendar: calendar,
            dayCount: 30
        )
    }

    private var maximum: Int {
        metrics.map(\.answerCount).max() ?? 0
    }

    var body: some View {
        if metrics.isEmpty {
            InsightsEmptyChartState(text: "最近 30 天还没有练习记录。")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("最近 30 天")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("共 \(metrics.reduce(0) { $0 + $1.answerCount }) 次回答")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                    spacing: 6
                ) {
                    ForEach(metrics) { metric in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(color(for: metric.answerCount))
                            .frame(height: 25)
                            .overlay {
                                if metric.answerCount > 0 {
                                    Text("\(metric.answerCount)")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(dateLabel(for: metric.date))
                            .accessibilityValue("回答 \(metric.answerCount) 次")
                    }
                }

                HStack(spacing: 8) {
                    Text("无")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 16, height: 16)
                    Text("少")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(legendColor(for: level))
                            .frame(width: 16, height: 16)
                    }
                    Text("活跃")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0, maximum > 0 else {
            return Color(uiColor: .tertiarySystemFill)
        }
        let ratio = Double(count) / Double(maximum)
        if ratio <= 0.25 { return InsightsDashboardPalette.cyan.opacity(0.45) }
        if ratio <= 0.5 { return InsightsDashboardPalette.cyan.opacity(0.68) }
        if ratio <= 0.75 { return InsightsDashboardPalette.blue.opacity(0.82) }
        return InsightsDashboardPalette.purple
    }

    private func legendColor(for level: Int) -> Color {
        switch level {
        case 0: InsightsDashboardPalette.cyan.opacity(0.45)
        case 1: InsightsDashboardPalette.cyan.opacity(0.68)
        case 2: InsightsDashboardPalette.blue.opacity(0.82)
        default: InsightsDashboardPalette.purple
        }
    }

    private func dateLabel(for date: Date) -> String {
        date.formatted(.dateTime.month().day())
    }
}

struct InsightsTopicProgressList: View {
    let snapshot: InsightsAggregator.Snapshot
    let selectedTopicID: UUID?

    var body: some View {
        if snapshot.topicSummaries.isEmpty {
            InsightsEmptyChartState(text: "添加 Topic 后会显示 Topic 对比。")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("覆盖率与平均分")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.topicSummaries) { topic in
                    topicRow(topic)
                }
            }
        }
    }

    private func topicRow(_ topic: InsightsAggregator.TopicSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(topic.id == selectedTopicID ? InsightsDashboardPalette.blue : InsightsDashboardPalette.purple.opacity(0.7))
                    .frame(width: 9, height: 9)
                Text(topic.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let averageScore = topic.averageScore {
                    Text("平均 \(averageScore)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(InsightsDashboardPalette.orange)
                } else {
                    Text("暂无评分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: topic.coverageRate)
                .tint(topic.id == selectedTopicID ? InsightsDashboardPalette.blue : InsightsDashboardPalette.purple.opacity(0.7))

            HStack {
                Text("覆盖率 \(Int((topic.coverageRate * 100).rounded()))%")
                Spacer()
                Text("已练习 \(topic.practicedCards)/\(topic.cardCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(topic.name)
        .accessibilityValue(
            "覆盖率 \(Int((topic.coverageRate * 100).rounded()))%，已练习 \(topic.practicedCards) 个，共 \(topic.cardCount) 个，平均分 \(topic.averageScore.map(String.init) ?? "暂无评分")"
        )
    }
}
