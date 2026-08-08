import Foundation

enum PracticeFeedEmptyReason: Equatable, Sendable {
    case globalLibraryEmpty
    case filteredPoolEmpty
}

enum PracticeFeedAction: Equatable, Sendable {
    case skipped(questionID: UUID)
    case answered(questionID: UUID)
}

struct PracticeFeedState: Equatable, Sendable {
    typealias EmptyReason = PracticeFeedEmptyReason
    typealias Action = PracticeFeedAction

    var selectedTopicIDs: Set<UUID>
    var includePracticed: Bool

    private(set) var currentQuestionID: UUID?
    private(set) var lastAction: PracticeFeedAction?

    init(
        selectedTopicIDs: Set<UUID> = [],
        includePracticed: Bool = false
    ) {
        self.selectedTopicIDs = selectedTopicIDs
        self.includePracticed = includePracticed
        currentQuestionID = nil
        lastAction = nil
    }

    func emptyReason(
        totalActiveCount: Int,
        eligibleCount: Int
    ) -> PracticeFeedEmptyReason? {
        if totalActiveCount <= 0 {
            return .globalLibraryEmpty
        }
        if eligibleCount <= 0 {
            return .filteredPoolEmpty
        }
        return nil
    }

    mutating func present(questionID: UUID) {
        currentQuestionID = questionID
    }

    mutating func present(_ questionID: UUID) {
        present(questionID: questionID)
    }

    @discardableResult
    mutating func skipCurrent() -> UUID? {
        guard let currentQuestionID else { return nil }

        self.currentQuestionID = nil
        lastAction = .skipped(questionID: currentQuestionID)
        return currentQuestionID
    }

    @discardableResult
    mutating func answerCurrent() -> UUID? {
        guard let currentQuestionID else { return nil }

        self.currentQuestionID = nil
        lastAction = .answered(questionID: currentQuestionID)
        return currentQuestionID
    }

    @discardableResult
    mutating func answerCurrent(questionID: UUID) -> Bool {
        guard currentQuestionID == questionID else { return false }
        _ = answerCurrent()
        return true
    }

    @discardableResult
    mutating func answerSubmitted(questionID: UUID) -> Bool {
        answerCurrent(questionID: questionID)
    }

    @discardableResult
    mutating func undoLastSwipe() -> UUID? {
        guard let lastAction else { return nil }

        let questionID: UUID
        switch lastAction {
        case let .skipped(id), let .answered(id):
            questionID = id
        }

        currentQuestionID = questionID
        self.lastAction = nil
        return questionID
    }

    @discardableResult
    mutating func undoLastSkip() -> UUID? {
        guard case .skipped = lastAction else { return nil }
        return undoLastSwipe()
    }
}
