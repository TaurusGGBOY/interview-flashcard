import CoreGraphics
import Foundation

enum PracticeSwipeAction: Equatable, Sendable {
    case skip
    case answer
}

struct PracticeSwipeInteraction: Sendable {
    static let distanceThresholdRatio: CGFloat = 0.32
    static let minimumHorizontalIntent: CGFloat = 12

    static func action(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        cardWidth: CGFloat
    ) -> PracticeSwipeAction? {
        guard cardWidth > 0 else { return nil }
        guard abs(translation.width) >= minimumHorizontalIntent else { return nil }
        guard abs(translation.width) > abs(translation.height) else { return nil }

        let threshold = cardWidth * distanceThresholdRatio
        guard abs(translation.width) >= threshold
            || abs(predictedEndTranslation.width) >= threshold
        else {
            return nil
        }

        return translation.width < 0 ? .skip : .answer
    }

    static func nextDrawPool(
        from cards: [QuestionCardSnapshot],
        excluding cardID: UUID?
    ) -> [QuestionCardSnapshot] {
        // A skip only prevents an immediate repeat when there is another card.
        // Do not retain a presented-ID set: skipped cards must re-enter the pool.
        guard let cardID, cards.count > 1 else { return cards }
        let alternatives = cards.filter { $0.id != cardID }
        return alternatives.isEmpty ? cards : alternatives
    }
}
