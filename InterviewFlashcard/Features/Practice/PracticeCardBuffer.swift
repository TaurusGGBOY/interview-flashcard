import Foundation

struct PracticeCardProductionRequest: Sendable {
    let generation: Int
    let snapshots: [QuestionCardSnapshot]
    let selectedTopicIDs: Set<UUID>
    let includePracticed: Bool
    let orderMode: PracticeOrderMode
    let progressQuestionID: UUID?
    let currentQuestionID: UUID?
    let queuedQuestionIDs: Set<UUID>
    let desiredCount: Int
    let seededGenerator: SeededPracticeRandomNumberGenerator?
}

struct PracticeCardProductionResult: Equatable, Sendable {
    let generation: Int
    let cards: [QuestionCardSnapshot]
    let seededGenerator: SeededPracticeRandomNumberGenerator?

    init(
        generation: Int,
        cards: [QuestionCardSnapshot],
        seededGenerator: SeededPracticeRandomNumberGenerator? = nil
    ) {
        self.generation = generation
        self.cards = cards
        self.seededGenerator = seededGenerator
    }
}

struct PracticeCardBuffer: Equatable, Sendable {
    static let capacity = 5

    private(set) var generation = 0
    private(set) var upcoming: [QuestionCardSnapshot] = []

    var count: Int { upcoming.count }
    var isEmpty: Bool { upcoming.isEmpty }
    var questionIDs: Set<UUID> { Set(upcoming.map(\.id)) }

    mutating func reset(generation: Int) {
        self.generation = generation
        upcoming.removeAll(keepingCapacity: true)
    }

    mutating func rebase(
        generation: Int,
        retaining allowedQuestionIDs: Set<UUID>
    ) {
        self.generation = generation
        upcoming.removeAll { !allowedQuestionIDs.contains($0.id) }
    }

    mutating func remove(questionID: UUID) {
        upcoming.removeAll { $0.id == questionID }
    }

    @discardableResult
    mutating func apply(_ result: PracticeCardProductionResult) -> Bool {
        guard result.generation == generation else { return false }

        let remainingCapacity = max(Self.capacity - upcoming.count, 0)
        guard remainingCapacity > 0 else { return true }

        var existingIDs = questionIDs
        for card in result.cards where !existingIDs.contains(card.id) {
            upcoming.append(card)
            existingIDs.insert(card.id)
            if upcoming.count == Self.capacity { break }
        }
        return true
    }

    mutating func consume() -> QuestionCardSnapshot? {
        guard !upcoming.isEmpty else { return nil }
        return upcoming.removeFirst()
    }
}

struct PracticeCardProducer: Sendable {
    private let drawService = QuestionDrawService()

    func produce(
        _ request: PracticeCardProductionRequest
    ) -> PracticeCardProductionResult {
        let desiredCount = max(request.desiredCount, 0)
        guard desiredCount > 0 else {
            return PracticeCardProductionResult(
                generation: request.generation,
                cards: [],
                seededGenerator: request.seededGenerator
            )
        }

        let cards: [QuestionCardSnapshot]
        var seededGenerator = request.seededGenerator
        switch request.orderMode {
        case .random:
            let eligible = drawService.eligibleCards(
                request.snapshots,
                topicIDs: request.selectedTopicIDs,
                includePracticed: request.includePracticed
            )
            var excludedIDs = request.queuedQuestionIDs
            if let currentQuestionID = request.currentQuestionID {
                excludedIDs.insert(currentQuestionID)
            }
            var candidates = eligible.filter { !excludedIDs.contains($0.id) }

            if candidates.isEmpty,
               request.queuedQuestionIDs.isEmpty,
               eligible.count == 1,
               eligible.first?.id == request.currentQuestionID {
                candidates = eligible
            }

            var selected: [QuestionCardSnapshot] = []
            selected.reserveCapacity(min(desiredCount, candidates.count))
            while !candidates.isEmpty && selected.count < desiredCount {
                let index: Int
                if var generator = seededGenerator {
                    index = Int.random(in: 0..<candidates.count, using: &generator)
                    seededGenerator = generator
                } else {
                    index = Int.random(in: 0..<candidates.count)
                }
                selected.append(candidates.remove(at: index))
            }
            cards = selected

        case .ascending, .descending:
            let sequenceCards = request.snapshots.filter { card in
                !card.isTrashed && request.selectedTopicIDs.contains(card.topicID)
            }
            let ordered = drawService.orderedCards(
                from: sequenceCards,
                mode: request.orderMode
            )
            let eligibleIDs = Set(drawService.eligibleCards(
                request.snapshots,
                topicIDs: request.selectedTopicIDs,
                includePracticed: request.includePracticed
            ).map(\.id))
            let startIndex = request.progressQuestionID.flatMap { progressID in
                ordered.firstIndex(where: { $0.id == progressID }).map { $0 + 1 }
            } ?? 0
            var excludedIDs = request.queuedQuestionIDs
            if let currentQuestionID = request.currentQuestionID {
                excludedIDs.insert(currentQuestionID)
            }
            cards = Array(ordered.dropFirst(startIndex).lazy.filter { card in
                eligibleIDs.contains(card.id) && !excludedIDs.contains(card.id)
            }.prefix(desiredCount))
        }

        return PracticeCardProductionResult(
            generation: request.generation,
            cards: cards,
            seededGenerator: seededGenerator
        )
    }
}
