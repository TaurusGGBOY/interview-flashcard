import Foundation

enum PracticeAccessibilityID {
    static let screen = "practice.screen"
    static let includePracticed = "practice.include-practiced"
    static let orderMode = "practice.order-mode"
    static let progress = "practice.progress"
    static let card = "practice.card"
    static let question = "practice.question"
    static let skip = "practice.skip"
    static let answer = "practice.answer"
    static let delete = "practice.delete"
    static let returnToQuestion = "practice.return-to-question"
    static let viewHistory = "practice.view-history"
    static let cardBack = "practice.card.back"
    static let cardBackSurface = "practice.card.back.surface"
    static let swipeHint = "practice.swipe-hint"
    static let skipIndicator = "practice.skip-indicator"
    static let answerIndicator = "practice.answer-indicator"
    static let deleteIndicator = "practice.delete-indicator"
    static let undo = "practice.undo"
    static let emptyLibrary = "practice.empty.library"
    static let radar = "evaluation.radar"
    static let evaluationRadar = radar
    static let details = "evaluation.details"
    static let evaluationDetails = details

    static func topic(_ id: UUID) -> String {
        "practice.topic.\(id.uuidString.lowercased())"
    }
}
