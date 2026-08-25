import CoreGraphics
import Foundation

enum PracticeSwipeAction: Equatable, Sendable {
    case skip
    case answer
    case delete
}

struct PracticeSwipeInteraction: Sendable {
    static let distanceThresholdRatio: CGFloat = 0.32
    static let minimumHorizontalIntent: CGFloat = 12
    static let exitPadding: CGFloat = 160

    static func action(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        cardWidth: CGFloat
    ) -> PracticeSwipeAction? {
        guard cardWidth > 0 else { return nil }

        let threshold = cardWidth * distanceThresholdRatio
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)

        if verticalDistance > horizontalDistance {
            guard translation.height < 0,
                  verticalDistance >= minimumHorizontalIntent,
                  verticalDistance >= threshold
                    || abs(predictedEndTranslation.height) >= threshold
            else { return nil }

            return .delete
        }

        guard horizontalDistance >= minimumHorizontalIntent,
              horizontalDistance >= threshold
                || abs(predictedEndTranslation.width) >= threshold
        else { return nil }

        return translation.width < 0 ? .skip : .answer
    }

    static func crossedDistanceThreshold(
        previousTranslation: CGSize,
        currentTranslation: CGSize,
        cardWidth: CGFloat
    ) -> Bool {
        guard cardWidth > 0 else { return false }
        let threshold = cardWidth * distanceThresholdRatio
        let isVerticalIntent = abs(currentTranslation.height) > abs(currentTranslation.width)
        if isVerticalIntent {
            guard currentTranslation.height < 0 else { return false }
        }
        let previousDistance = isVerticalIntent
            ? abs(previousTranslation.height)
            : abs(previousTranslation.width)
        let currentDistance = isVerticalIntent
            ? abs(currentTranslation.height)
            : abs(currentTranslation.width)
        return previousDistance < threshold && currentDistance >= threshold
    }

    static func exitOffset(
        for action: PracticeSwipeAction,
        cardSize: CGSize
    ) -> CGSize {
        switch action {
        case .skip:
            CGSize(width: -(cardSize.width + exitPadding), height: 0)
        case .answer:
            CGSize(width: cardSize.width + exitPadding, height: 0)
        case .delete:
            CGSize(width: 0, height: -(cardSize.height + exitPadding))
        }
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
