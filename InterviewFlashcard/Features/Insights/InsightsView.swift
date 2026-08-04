import SwiftData
import SwiftUI

enum InsightsAccessibilityID {
    static let screen = "insights.screen"
    static let metrics = "insights.metrics"
    static let topics = "insights.topics"
    static let dimensions = "insights.dimensions"
    static let trend = "insights.trend"
}

struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [QuestionCardRecord]
    @Query private var attempts: [AnswerAttemptRecord]

    private var snapshot: InsightsAggregator.Snapshot {
        InsightsAggregator().snapshot(
            asOf: Date(),
            calendar: Self.calendar,
            cards: cards,
            attempts: attempts
        )
    }

    var body: some View {
        List {
            Section("总览") {
                metric("题目", "\(snapshot.totalCards)")
                metric("已练习", "\(snapshot.practicedCards)")
                metric("未练习", "\(snapshot.unpracticedCards)")
                metric("覆盖率", "\(Int((snapshot.coverageRate * 100).rounded()))%")
                metric("回答次数", "\(snapshot.answerCount)")
                metric("练习天数", "\(snapshot.practiceDays)")
                metric("平均分", "\(snapshot.averageScore)")
            }
            .accessibilityIdentifier(InsightsAccessibilityID.metrics)

            Section("六维平均分") {
                ForEach(ScoreDimension.allCases, id: \.self) { dimension in
                    LabeledContent(dimension.displayName, value: "\(snapshot.averageDimensions[dimension])")
                }
            }
            .accessibilityIdentifier(InsightsAccessibilityID.dimensions)

            Section("Topic") {
                if snapshot.topicSummaries.isEmpty {
                    Text("还没有题目")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.topicSummaries) { topic in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(topic.name)
                                Spacer()
                                Text("\(topic.practicedCards)/\(topic.cardCount)")
                            }
                            Text("覆盖 \(Int((topic.coverageRate * 100).rounded()))% · 平均 \(topic.averageScore.map(String.init) ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier(InsightsAccessibilityID.topics)

            Section("练习趋势") {
                ForEach(snapshot.trend) { point in
                    LabeledContent(
                        point.date.formatted(date: .abbreviated, time: .omitted),
                        value: "\(point.answerCount) 次 · \(point.averageScore.map { "平均 \($0)" } ?? "未评分")"
                    )
                }
                if snapshot.trend.isEmpty {
                    Text("完成一次回答后会显示趋势。")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier(InsightsAccessibilityID.trend)
        }
        .navigationTitle("统计")
        .accessibilityIdentifier(InsightsAccessibilityID.screen)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
