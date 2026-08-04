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

    struct Snapshot: Equatable, Sendable {
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

    func snapshot(
        asOf: Date,
        calendar: Calendar,
        cards: [CardInput],
        attempts: [AttemptInput]
    ) -> Snapshot {
        let activeCards = cards.filter { !$0.isTrashed }
        let activeIDs = Set(activeCards.map(\.id))
        let activeAttempts = attempts.filter { activeIDs.contains($0.questionID) }
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
        let topicSummaries = activeCards
            .reduce(into: [UUID: (name: String, cards: Int, practiced: Set<UUID>, scores: [Int])]()) { result, card in
                var value = result[card.topicID] ?? (card.topicName, 0, [], [])
                value.cards += 1
                if practicedIDs.contains(card.id) { value.practiced.insert(card.id) }
                let cardScores = scored.filter { $0.0.questionID == card.id }.compactMap { $0.1.totalScore }
                value.scores.append(contentsOf: cardScores)
                result[card.topicID] = value
            }
            .map { id, value in
                TopicSummary(
                    id: id,
                    name: value.name,
                    cardCount: value.cards,
                    practicedCards: value.practiced.count,
                    coverageRate: value.cards == 0 ? 0 : Double(value.practiced.count) / Double(value.cards),
                    averageScore: value.scores.isEmpty ? nil : Int(Double(value.scores.reduce(0, +)) / Double(value.scores.count).rounded())
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let trend = Dictionary(grouping: activeAttempts) { calendar.startOfDay(for: $0.submittedAt) }
            .map { date, dayAttempts in
                let dayScores = dayAttempts.compactMap { attempt in
                    guard let evaluation = attempt.evaluation, evaluation.status == .completed else { return nil }
                    return evaluation.totalScore
                }
                return TrendPoint(
                    date: date,
                    answerCount: dayAttempts.count,
                    averageScore: dayScores.isEmpty ? nil : Int(Double(dayScores.reduce(0, +)) / Double(dayScores.count).rounded())
                )
            }
            .sorted { $0.date < $1.date }

        return Snapshot(
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
            averageScore: scores.isEmpty ? 0 : Int(Double(scores.reduce(0, +)) / Double(scores.count).rounded()),
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
        attempts: [AnswerAttemptRecord]
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
        return snapshot(asOf: asOf, calendar: calendar, cards: cardInputs, attempts: attemptInputs)
    }

    private func averageDimensionScores(_ evaluations: [EvaluationInput]) -> DimensionScores {
        guard !evaluations.isEmpty else { return .init(correctness: 0, coverage: 0, reasoning: 0, structure: 0, tradeoffs: 0, precision: 0) }
        func avg(_ keyPath: KeyPath<DimensionScores, Int>) -> Int {
            Int(Double(evaluations.map { $0.dimensions[keyPath: keyPath] }.reduce(0, +)) / Double(evaluations.count).rounded())
        }
        return DimensionScores(
            correctness: avg(\.correctness), coverage: avg(\.coverage), reasoning: avg(\.reasoning),
            structure: avg(\.structure), tradeoffs: avg(\.tradeoffs), precision: avg(\.precision)
        )
    }
}
