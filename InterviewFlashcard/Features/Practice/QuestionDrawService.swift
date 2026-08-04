import Foundation

struct QuestionCardSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let topicID: UUID
    let topicName: String
    let questionText: String
    let isTrashed: Bool
    let hasSubmittedAttempt: Bool

    init(
        id: UUID,
        topicID: UUID,
        topicName: String,
        questionText: String,
        isTrashed: Bool,
        hasSubmittedAttempt: Bool
    ) {
        self.id = id
        self.topicID = topicID
        self.topicName = topicName
        self.questionText = questionText
        self.isTrashed = isTrashed
        self.hasSubmittedAttempt = hasSubmittedAttempt
    }

    init(record: QuestionCardRecord) {
        self.init(
            id: record.id,
            topicID: record.topic.id,
            topicName: record.topic.systemKind == .others ? "待分类（Others）" : record.topic.name,
            questionText: record.questionText,
            isTrashed: record.isTrashed,
            hasSubmittedAttempt: !record.attempts.isEmpty
        )
    }
}

struct QuestionDrawService: Sendable {
    func eligibleCards(
        _ cards: [QuestionCardSnapshot],
        topicIDs: Set<UUID>,
        includePracticed: Bool
    ) -> [QuestionCardSnapshot] {
        guard !topicIDs.isEmpty else { return [] }
        return cards.filter { card in
            !card.isTrashed
                && topicIDs.contains(card.topicID)
                && (includePracticed || !card.hasSubmittedAttempt)
        }
    }

    func draw<RNG: RandomNumberGenerator>(
        from cards: [QuestionCardSnapshot],
        using generator: inout RNG
    ) -> QuestionCardSnapshot? {
        guard !cards.isEmpty else { return nil }
        let index = Int.random(in: 0..<cards.count, using: &generator)
        return cards[index]
    }

    func draw(from cards: [QuestionCardSnapshot]) -> QuestionCardSnapshot? {
        var generator = SystemRandomNumberGenerator()
        return draw(from: cards, using: &generator)
    }
}

struct SeededPracticeRandomNumberGenerator: RandomNumberGenerator, Equatable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
