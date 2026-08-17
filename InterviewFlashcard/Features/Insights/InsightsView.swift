import SwiftData
import SwiftUI
import UIKit

enum InsightsAccessibilityID {
    static let screen = "insights.screen"
    static let filter = "insights.filter"
    static let metrics = "insights.metrics"
    static let scores = "insights.scores"
    static let activity = "insights.activity"
    static let topics = "insights.topics"
    static let dimensions = "insights.dimensions"
    static let trend = "insights.trend"
}

struct InsightsView: View {
    @Query private var cards: [QuestionCardRecord]
    @Query private var attempts: [AnswerAttemptRecord]
    @SceneStorage("insights.selectedScopeID") private var selectedScopeID = "all"

    private var allSnapshot: InsightsAggregator.Snapshot {
        InsightsAggregator().snapshot(
            asOf: Date(),
            calendar: Self.calendar,
            cards: cards,
            attempts: attempts,
            scope: .all
        )
    }

    private var selectedTopicID: UUID? {
        guard selectedScopeID != "all",
              let topicID = UUID(uuidString: selectedScopeID),
              allSnapshot.topicSummaries.contains(where: { $0.id == topicID }) else {
            return nil
        }
        return topicID
    }

    private var selectedScope: InsightsAggregator.Scope {
        selectedTopicID.map(InsightsAggregator.Scope.topic) ?? .all
    }

    private var snapshot: InsightsAggregator.Snapshot {
        InsightsAggregator().snapshot(
            asOf: Date(),
            calendar: Self.calendar,
            cards: cards,
            attempts: attempts,
            scope: selectedScope
        )
    }

    private var scopeName: String {
        InsightsChartData.scopeDescription(for: snapshot.scope, topics: allSnapshot.topicSummaries)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    scopePicker

                    if allSnapshot.totalCards == 0 {
                        ContentUnavailableView(
                            "还没有统计数据",
                            systemImage: "chart.bar.xaxis",
                            description: Text("导入题目或手动添加题目后，这里会显示图表。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        InsightsOverviewCard(snapshot: snapshot, scopeName: scopeName)

                        InsightsChartCard(
                            title: "分数概览",
                            subtitle: "已完成评分的回答",
                            systemImage: "chart.bar.fill",
                            accessibilityID: InsightsAccessibilityID.scores,
                            accessibilityLabel: "分数概览",
                            accessibilityValue: scoreAccessibilityValue
                        ) {
                            InsightsScoreChart(snapshot: snapshot)
                        }

                        InsightsChartCard(
                            title: "练习活动",
                            subtitle: "最近 30 天的回答热力图",
                            systemImage: "bolt.fill",
                            accessibilityID: InsightsAccessibilityID.activity,
                            accessibilityLabel: "练习活动",
                            accessibilityValue: activityAccessibilityValue
                        ) {
                            InsightsActivityChart(snapshot: snapshot)
                        }

                        InsightsChartCard(
                            title: "六维能力",
                            subtitle: "已评分回答的维度平均分",
                            systemImage: "hexagon",
                            accessibilityID: InsightsAccessibilityID.dimensions,
                            accessibilityLabel: "六维能力",
                            accessibilityValue: dimensionsAccessibilityValue
                        ) {
                            InsightsDimensionsChart(snapshot: snapshot)
                        }

                        InsightsChartCard(
                            title: "Topic 对比",
                            subtitle: "所有活跃 Topic 的覆盖率与平均分",
                            systemImage: "square.grid.2x2.fill",
                            accessibilityID: InsightsAccessibilityID.topics,
                            accessibilityLabel: "Topic 对比",
                            accessibilityValue: topicsAccessibilityValue
                        ) {
                            InsightsTopicsChart(snapshot: allSnapshot, selectedTopicID: selectedTopicID)
                        }

                        InsightsChartCard(
                            title: "练习趋势",
                            subtitle: "按天查看分数与回答次数",
                            systemImage: "chart.xyaxis.line",
                            accessibilityID: InsightsAccessibilityID.trend,
                            accessibilityLabel: "练习趋势",
                            accessibilityValue: trendAccessibilityValue
                        ) {
                            InsightsTrendChart(snapshot: snapshot)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier(InsightsAccessibilityID.screen)
        .onAppear(perform: normalizeSelection)
        .onChange(of: allSnapshot.topicSummaries.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("查看范围", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)

            Picker("查看范围", selection: $selectedScopeID) {
                Text("全部 Topic").tag("all")
                ForEach(allSnapshot.topicSummaries) { topic in
                    Text(topic.name).tag(topic.id.uuidString)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier(InsightsAccessibilityID.filter)

            Text("当前范围：\(scopeName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var coverageAccessibilityValue: String {
        "\(snapshot.practicedCards) 个已练习，\(snapshot.unpracticedCards) 个未练习，覆盖率 \(Int((snapshot.coverageRate * 100).rounded()))%"
    }

    private var scoreAccessibilityValue: String {
        guard snapshot.scoredAnswerCount > 0 else { return "暂无评分数据" }
        let latest = snapshot.latestScore.map(String.init) ?? "暂无"
        let best = snapshot.bestScore.map(String.init) ?? "暂无"
        return "平均分 \(snapshot.averageScore)，最近一次 \(latest)，最高分 \(best)"
    }

    private var activityAccessibilityValue: String {
        guard snapshot.answerCount > 0 else { return "暂无练习活动" }
        return "回答 \(snapshot.answerCount) 次，已评分 \(snapshot.scoredAnswerCount) 次，未评分 \(snapshot.unscoredAnswerCount) 次，练习 \(snapshot.practiceDays) 天，近 7 日 \(snapshot.sevenDayAnswerCount) 次，近 30 日 \(snapshot.thirtyDayAnswerCount) 次"
    }

    private var dimensionsAccessibilityValue: String {
        guard snapshot.scoredAnswerCount > 0 else { return "暂无六维评分数据" }
        return ScoreDimension.allCases.map { "\($0.displayName) \(snapshot.averageDimensions[$0])" }.joined(separator: "，")
    }

    private var topicsAccessibilityValue: String {
        guard !allSnapshot.topicSummaries.isEmpty else { return "暂无 Topic 数据" }
        return allSnapshot.topicSummaries.map { topic in
            let score = topic.averageScore.map(String.init) ?? "暂无评分"
            return "\(topic.name)，覆盖率 \(Int((topic.coverageRate * 100).rounded()))%，平均分 \(score)"
        }.joined(separator: "；")
    }

    private var trendAccessibilityValue: String {
        guard !snapshot.trend.isEmpty else { return "暂无趋势数据" }
        return "共 \(snapshot.trend.count) 天，\(snapshot.trend.map(\.answerCount).reduce(0, +)) 次回答"
    }

    private func normalizeSelection() {
        guard selectedScopeID != "all" else { return }
        if selectedTopicID == nil {
            selectedScopeID = "all"
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
