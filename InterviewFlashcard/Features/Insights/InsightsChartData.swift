import Foundation

struct InsightsChartData {
    enum CoverageKind: String, Equatable, Sendable {
        case practiced
        case unpracticed

        var displayName: String {
            switch self {
            case .practiced: "已练习"
            case .unpracticed: "未练习"
            }
        }
    }

    struct CoverageSegment: Equatable, Identifiable, Sendable {
        let kind: CoverageKind
        let value: Int
        var id: CoverageKind { kind }
        var label: String { kind.displayName }
    }

    enum ScoreKind: String, Equatable, Sendable {
        case average
        case latest
        case best

        var displayName: String {
            switch self {
            case .average: "平均分"
            case .latest: "最近一次"
            case .best: "最高分"
            }
        }
    }

    struct ScoreMetric: Equatable, Identifiable, Sendable {
        let kind: ScoreKind
        let value: Int
        var id: ScoreKind { kind }
        var label: String { kind.displayName }
    }

    enum ActivityKind: String, Equatable, Sendable {
        case answers
        case scoredAnswers
        case unscoredAnswers
        case practiceDays
        case lastSevenDays
        case lastThirtyDays

        var displayName: String {
            switch self {
            case .answers: "总回答"
            case .scoredAnswers: "已评分"
            case .unscoredAnswers: "未评分"
            case .practiceDays: "练习天数"
            case .lastSevenDays: "近 7 日"
            case .lastThirtyDays: "近 30 日"
            }
        }
    }

    struct ActivityMetric: Equatable, Identifiable, Sendable {
        let kind: ActivityKind
        let value: Int
        var id: ActivityKind { kind }
        var label: String { kind.displayName }
    }

    struct DimensionMetric: Equatable, Identifiable, Sendable {
        let dimension: ScoreDimension
        let value: Int
        var id: ScoreDimension { dimension }
        var label: String { dimension.displayName }
    }

    enum TopicMetricKind: String, Equatable, Sendable {
        case coverage
        case averageScore

        var displayName: String {
            switch self {
            case .coverage: "覆盖率"
            case .averageScore: "平均分"
            }
        }
    }

    struct TopicMetric: Equatable, Identifiable, Sendable {
        let topicID: UUID
        let topicName: String
        let kind: TopicMetricKind
        let value: Int

        var id: String { "\(topicID.uuidString)-\(kind.rawValue)" }
        var label: String { topicName }
    }

    struct TrendMetric: Equatable, Identifiable, Sendable {
        let date: Date
        let answerCount: Int
        let averageScore: Int?
        var id: Date { date }
    }

    struct DailyActivityMetric: Equatable, Identifiable, Sendable {
        let date: Date
        let answerCount: Int
        var id: Date { date }
    }

    static func coverageSegments(from snapshot: InsightsAggregator.Snapshot) -> [CoverageSegment] {
        guard snapshot.totalCards > 0 else { return [] }
        return [
            CoverageSegment(kind: .practiced, value: snapshot.practicedCards),
            CoverageSegment(kind: .unpracticed, value: snapshot.unpracticedCards),
        ].filter { $0.value > 0 }
    }

    static func scoreMetrics(from snapshot: InsightsAggregator.Snapshot) -> [ScoreMetric] {
        guard snapshot.scoredAnswerCount > 0 else { return [] }
        var metrics = [
            ScoreMetric(kind: .average, value: snapshot.averageScore),
        ]
        if let latestScore = snapshot.latestScore {
            metrics.append(ScoreMetric(kind: .latest, value: latestScore))
        }
        if let bestScore = snapshot.bestScore {
            metrics.append(ScoreMetric(kind: .best, value: bestScore))
        }
        return metrics
    }

    static func activityMetrics(from snapshot: InsightsAggregator.Snapshot) -> [ActivityMetric] {
        guard snapshot.answerCount > 0 else { return [] }
        return [
            ActivityMetric(kind: .answers, value: snapshot.answerCount),
            ActivityMetric(kind: .scoredAnswers, value: snapshot.scoredAnswerCount),
            ActivityMetric(kind: .unscoredAnswers, value: snapshot.unscoredAnswerCount),
            ActivityMetric(kind: .practiceDays, value: snapshot.practiceDays),
            ActivityMetric(kind: .lastSevenDays, value: snapshot.sevenDayAnswerCount),
            ActivityMetric(kind: .lastThirtyDays, value: snapshot.thirtyDayAnswerCount),
        ]
    }

    static func dimensionMetrics(from snapshot: InsightsAggregator.Snapshot) -> [DimensionMetric] {
        guard snapshot.scoredAnswerCount > 0 else { return [] }
        return ScoreDimension.allCases.map { dimension in
            DimensionMetric(dimension: dimension, value: snapshot.averageDimensions[dimension])
        }
    }

    static func topicMetrics(from snapshot: InsightsAggregator.Snapshot) -> [TopicMetric] {
        snapshot.topicSummaries.flatMap { topic in
            var metrics = [
                TopicMetric(
                    topicID: topic.id,
                    topicName: topic.name,
                    kind: .coverage,
                    value: Int((topic.coverageRate * 100).rounded())
                ),
            ]
            if let averageScore = topic.averageScore {
                metrics.append(TopicMetric(
                    topicID: topic.id,
                    topicName: topic.name,
                    kind: .averageScore,
                    value: averageScore
                ))
            }
            return metrics
        }
    }

    static func trendMetrics(from snapshot: InsightsAggregator.Snapshot) -> [TrendMetric] {
        snapshot.trend.map {
            TrendMetric(date: $0.date, answerCount: $0.answerCount, averageScore: $0.averageScore)
        }
    }

    static func activityHeatmapMetrics(
        from snapshot: InsightsAggregator.Snapshot,
        asOf: Date,
        calendar: Calendar,
        dayCount: Int = 30
    ) -> [DailyActivityMetric] {
        guard dayCount > 0, !snapshot.trend.isEmpty else { return [] }

        let endDate = calendar.startOfDay(for: asOf)
        let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDate) ?? endDate
        let countsByDay = snapshot.trend.reduce(into: [Date: Int]()) { counts, point in
            let date = calendar.startOfDay(for: point.date)
            counts[date, default: 0] += point.answerCount
        }

        let metrics = (0..<dayCount).compactMap { offset -> DailyActivityMetric? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }
            return DailyActivityMetric(date: date, answerCount: countsByDay[date, default: 0])
        }

        return metrics.contains(where: { $0.answerCount > 0 }) ? metrics : []
    }

    static func scopeDescription(for scope: InsightsAggregator.Scope, topics: [InsightsAggregator.TopicSummary]) -> String {
        switch scope {
        case .all:
            return "全部 Topic"
        case let .topic(topicID):
            return topics.first(where: { $0.id == topicID })?.name ?? "已选 Topic"
        }
    }
}
