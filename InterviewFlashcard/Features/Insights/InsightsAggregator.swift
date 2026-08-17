import Foundation

struct InsightsAggregator {
    struct CardInput: Equatable, Sendable {
        let id: UUID
        let topicID: UUID
        let topicName: String
        let isTrashed: Bool

        init(id: UUID, topicID: UUID, topicName: String, isTrashed: Bool = false) {
            self.id = id
            self.topicID = topicID
            self.topicName = topicName
            self.isTrashed = isTrashed
        }
    }

    struct EvaluationInput: Equatable, Sendable {
        let totalScore: Int?
        let dimensions: DimensionScores
        let status: EvaluationStatus

        init(totalScore: Int?, dimensions: DimensionScores, status: EvaluationStatus = .completed) {
            self.totalScore = totalScore
            self.dimensions = dimensions
            self.status = status
        }
    }

    struct AttemptInput: Equatable, Sendable {
        let id: UUID
        let questionID: UUID
        let submittedAt: Date
        let evaluation: EvaluationInput?

        init(id: UUID, questionID: UUID, submittedAt: Date, evaluation: EvaluationInput? = nil) {
            self.id = id
            self.questionID = questionID
            self.submittedAt = submittedAt
            self.evaluation = evaluation
        }
    }

    struct TopicSummary: Equatable, Sendable, Identifiable {
        let id: UUID
        let name: String
        let cardCount: Int
        let practicedCards: Int
        let coverageRate: Double
        let averageScore: Int?
    }

    struct TrendPoint: Equatable, Sendable, Identifiable {
        let date: Date
        let answerCount: Int
        let averageScore: Int?
        var id: Date { date }
    }

    enum Scope: Equatable, Sendable {
        case all
        case topic(UUID)
    }

    struct Snapshot: Equatable, Sendable {
        let scope: Scope
        let totalCards: Int
        let practicedCards: Int
        let unpracticedCards: Int
        let coverageRate: Double
        let answerCount: Int
        let scoredAnswerCount: Int
        let unscoredAnswerCount: Int
        let practiceDays: Int
        let sevenDayAnswerCount: Int
        let thirtyDayAnswerCount: Int
        let averageScore: Int
        let latestScore: Int?
        let bestScore: Int?
        let averageDimensions: DimensionScores
        let topicSummaries: [TopicSummary]
        let trend: [TrendPoint]
    }

    private struct TopicBucket {
        let name: String
        var cardCount = 0
        var practicedCards = Set<UUID>()
        var scores = [Int]()
    }

    func snapshot(
        asOf: Date,
        calendar: Calendar,
        cards: [CardInput],
        attempts: [AttemptInput],
        scope: Scope = .all
    ) -> Snapshot {
        let allActiveCards = cards.filter { !$0.isTrashed }
        let allActiveIDs = Set(allActiveCards.map(\.id))
        let allActiveAttempts = attempts.filter { allActiveIDs.contains($0.questionID) }
        let allPracticedIDs = Set(allActiveAttempts.map(\.questionID))
        let allScored = allActiveAttempts.compactMap { attempt -> (AttemptInput, EvaluationInput)? in
            guard let evaluation = attempt.evaluation,
                  evaluation.status == .completed,
                  evaluation.totalScore != nil else { return nil }
            return (attempt, evaluation)
        }

        let scoredByQuestion: [UUID: [(AttemptInput, EvaluationInput)]] = Dictionary(grouping: allScored) { $0.0.questionID }
        let topicBuckets = allActiveCards.reduce(into: [UUID: TopicBucket]()) { buckets, card in
            var bucket = buckets[card.topicID] ?? TopicBucket(name: card.topicName)
            bucket.cardCount += 1
            if allPracticedIDs.contains(card.id) {
                bucket.practicedCards.insert(card.id)
            }
            bucket.scores.append(contentsOf: scoredByQuestion[card.id, default: []].compactMap { $0.1.totalScore })
            buckets[card.topicID] = bucket
        }

        let topicSummaries = topicBuckets
            .map { id, bucket in
                TopicSummary(
                    id: id,
                    name: bucket.name,
                    cardCount: bucket.cardCount,
                    practicedCards: bucket.practicedCards.count,
                    coverageRate: bucket.cardCount == 0 ? 0 : Double(bucket.practicedCards.count) / Double(bucket.cardCount),
                    averageScore: bucket.scores.isEmpty ? nil : average(bucket.scores)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let activeCards: [CardInput]
        switch scope {
        case .all:
            activeCards = allActiveCards
        case let .topic(topicID):
            activeCards = allActiveCards.filter { $0.topicID == topicID }
        }
        let activeIDs = Set(activeCards.map(\.id))
        let activeAttempts = allActiveAttempts.filter { activeIDs.contains($0.questionID) }
        let scored = activeAttempts.compactMap { attempt -> (AttemptInput, EvaluationInput)? in
            guard let evaluation = attempt.evaluation,
                  evaluation.status == .completed,
                  evaluation.totalScore != nil else { return nil }
            return (attempt, evaluation)
        }
        let scores = scored.compactMap { $0.1.totalScore }
        let practicedIDs = Set(activeAttempts.map(\.questionID))
        let practiceDays = Set(activeAttempts.map { calendar.startOfDay(for: $0.submittedAt) }).count
        let startOfToday = calendar.startOfDay(for: asOf)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday

        let averageDimensions = averageDimensionScores(scored.map(\.1))

        let groupedTrend: [Date: [AttemptInput]] = Dictionary(grouping: activeAttempts) {
            calendar.startOfDay(for: $0.submittedAt)
        }
        let trend: [TrendPoint] = groupedTrend
            .map { (date: Date, dayAttempts: [AttemptInput]) -> TrendPoint in
                let dayScores: [Int] = dayAttempts.compactMap { (attempt: AttemptInput) -> Int? in
                    guard let evaluation = attempt.evaluation,
                          evaluation.status == .completed,
                          let totalScore = evaluation.totalScore else { return nil }
                    return totalScore
                }
                return TrendPoint(
                    date: date,
                    answerCount: dayAttempts.count,
                    averageScore: dayScores.isEmpty ? nil : Int(Double(dayScores.reduce(0, +)) / Double(dayScores.count).rounded())
                )
            }
            .sorted { $0.date < $1.date }

        return Snapshot(
            scope: scope,
            totalCards: activeCards.count,
            practicedCards: practicedIDs.count,
            unpracticedCards: max(0, activeCards.count - practicedIDs.count),
            coverageRate: activeCards.isEmpty ? 0 : Double(practicedIDs.count) / Double(activeCards.count),
            answerCount: activeAttempts.count,
            scoredAnswerCount: scores.count,
            unscoredAnswerCount: activeAttempts.count - scores.count,
            practiceDays: practiceDays,
            sevenDayAnswerCount: activeAttempts.filter { $0.submittedAt >= sevenDayStart && $0.submittedAt <= asOf }.count,
            thirtyDayAnswerCount: activeAttempts.filter { $0.submittedAt >= thirtyDayStart && $0.submittedAt <= asOf }.count,
            averageScore: scores.isEmpty ? 0 : average(scores),
            latestScore: scored.sorted { $0.0.submittedAt > $1.0.submittedAt }.first?.1.totalScore,
            bestScore: scores.max(),
            averageDimensions: averageDimensions,
            topicSummaries: topicSummaries,
            trend: trend
        )
    }

    @MainActor
    func snapshot(
        asOf: Date,
        calendar: Calendar,
        cards: [QuestionCardRecord],
        attempts: [AnswerAttemptRecord],
        scope: Scope = .all
    ) -> Snapshot {
        let cardInputs = cards.map {
            CardInput(id: $0.id, topicID: $0.topic.id, topicName: $0.topic.name, isTrashed: $0.isTrashed)
        }
        let attemptInputs = attempts.map { attempt in
            let evaluation = attempt.evaluations.max { $0.createdAt < $1.createdAt }.map {
                EvaluationInput(totalScore: $0.totalScore, dimensions: $0.dimensionScores, status: $0.status)
            }
            return AttemptInput(id: attempt.id, questionID: attempt.question.id, submittedAt: attempt.submittedAt, evaluation: evaluation)
        }
        return snapshot(asOf: asOf, calendar: calendar, cards: cardInputs, attempts: attemptInputs, scope: scope)
    }

    private func averageDimensionScores(_ evaluations: [EvaluationInput]) -> DimensionScores {
        guard !evaluations.isEmpty else { return .init(correctness: 0, coverage: 0, reasoning: 0, structure: 0, tradeoffs: 0, precision: 0) }
        func avg(_ keyPath: KeyPath<DimensionScores, Int>) -> Int {
            average(evaluations.map { $0.dimensions[keyPath: keyPath] })
        }
        return DimensionScores(
            correctness: avg(\.correctness), coverage: avg(\.coverage), reasoning: avg(\.reasoning),
            structure: avg(\.structure), tradeoffs: avg(\.tradeoffs), precision: avg(\.precision)
        )
    }

    private func average(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int(Double(values.reduce(0, +)) / Double(values.count))
    }
}
