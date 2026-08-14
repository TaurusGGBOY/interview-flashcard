import Foundation

@MainActor
enum LibraryQuestionOrdering {
    static func newestFirst(
        _ lhs: QuestionCardRecord,
        _ rhs: QuestionCardRecord
    ) -> Bool {
        switch (lhs.questionNumber, rhs.questionNumber) {
        case let (lhsNumber?, rhsNumber?) where lhsNumber != rhsNumber:
            return lhsNumber > rhsNumber
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
