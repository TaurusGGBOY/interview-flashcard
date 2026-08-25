import Foundation

struct QuestionCardSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let topicID: UUID
    let topicName: String
    let questionText: String
    let questionNumber: Int?
    let createdAt: Date
    let activatedAt: Date
    let isTrashed: Bool
    let hasSubmittedAttempt: Bool

    init(
        id: UUID,
        topicID: UUID,
        topicName: String,
        questionText: String,
        questionNumber: Int? = nil,
        createdAt: Date = .distantPast,
        activatedAt: Date = .distantPast,
        isTrashed: Bool,
        hasSubmittedAttempt: Bool
    ) {
        self.id = id
        self.topicID = topicID
        self.topicName = topicName
        self.questionText = questionText
        self.questionNumber = questionNumber
        self.createdAt = createdAt
        self.activatedAt = activatedAt
        self.isTrashed = isTrashed
        self.hasSubmittedAttempt = hasSubmittedAttempt
    }

    init(record: QuestionCardRecord) {
        self.init(
            id: record.id,
            topicID: record.topic.id,
            topicName: record.topic.systemKind == .others ? "待分类（Others）" : record.topic.name,
            questionText: record.questionText,
            questionNumber: record.questionNumber,
            createdAt: record.createdAt,
            activatedAt: record.activatedAt,
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

    func orderedCards(
        from cards: [QuestionCardSnapshot],
        mode: PracticeOrderMode
    ) -> [QuestionCardSnapshot] {
        cards.sorted { lhs, rhs in
            switch (lhs.questionNumber, rhs.questionNumber) {
            case let (left?, right?) where left != right:
                return mode == .descending ? left > right : left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.activatedAt != rhs.activatedAt {
                    return mode == .descending
                        ? lhs.activatedAt > rhs.activatedAt
                        : lhs.activatedAt < rhs.activatedAt
                }
                if lhs.createdAt != rhs.createdAt {
                    return mode == .descending
                        ? lhs.createdAt > rhs.createdAt
                        : lhs.createdAt < rhs.createdAt
                }
                return mode == .descending
                    ? lhs.id.uuidString > rhs.id.uuidString
                    : lhs.id.uuidString < rhs.id.uuidString
            }
        }
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
