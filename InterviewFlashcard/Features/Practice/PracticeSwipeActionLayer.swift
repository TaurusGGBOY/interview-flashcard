import SwiftUI
import UIKit

struct PracticeSwipeActionLayer<Content: View>: View {
    let cardWidth: CGFloat
    let isInteractionDisabled: Bool
    let skipTitle: String
    let skipSystemImage: String
    let answerTitle: String
    let answerSystemImage: String
    let canDelete: Bool
    let deleteTitle: String
    let deleteSystemImage: String
    let onCommit: (PracticeSwipeAction) -> Void
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation: CGSize = .zero
    @State private var previousTranslation: CGSize = .zero
    @State private var didCrossThreshold = false

    init(
        cardWidth: CGFloat,
        isInteractionDisabled: Bool,
        skipTitle: String = "跳过",
        skipSystemImage: String = "xmark",
        answerTitle: String = "开始回答",
        answerSystemImage: String = "pencil.and.outline",
        canDelete: Bool = true,
        deleteTitle: String = "删除本题",
        deleteSystemImage: String = "trash",
        onCommit: @escaping (PracticeSwipeAction) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cardWidth = cardWidth
        self.isInteractionDisabled = isInteractionDisabled
        self.skipTitle = skipTitle
        self.skipSystemImage = skipSystemImage
        self.answerTitle = answerTitle
        self.answerSystemImage = answerSystemImage
        self.canDelete = canDelete
        self.deleteTitle = deleteTitle
        self.deleteSystemImage = deleteSystemImage
        self.onCommit = onCommit
        self.content = content()
    }

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                swipeIndicator(title: answerTitle, systemImage: answerSystemImage, color: .green)
                    .padding(24)
                    .opacity(indicatorOpacity(for: .answer))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(PracticeAccessibilityID.answerIndicator)
            }
            .overlay(alignment: .topTrailing) {
                swipeIndicator(title: skipTitle, systemImage: skipSystemImage, color: .red)
                    .padding(24)
                    .opacity(indicatorOpacity(for: .skip))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(PracticeAccessibilityID.skipIndicator)
            }
            .overlay(alignment: .bottom) {
                swipeIndicator(title: deleteTitle, systemImage: deleteSystemImage, color: .red)
                    .padding(24)
                    .opacity(canDelete ? indicatorOpacity(for: .delete) : 0)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(PracticeAccessibilityID.deleteIndicator)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .offset(x: dragTranslation.width, y: dragTranslation.height)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragTranslation.width / max(cardWidth, 1)) * 7))
            .simultaneousGesture(dragGesture)
            .allowsHitTesting(!isInteractionDisabled)
            .accessibilityAction(named: skipTitle) {
                commit(.skip)
            }
            .accessibilityAction(named: answerTitle) {
                commit(.answer)
            }
            .accessibilityAction(named: deleteTitle) {
                commit(.delete)
            }
            .onChange(of: cardWidth) { _, _ in
                dragTranslation = .zero
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isInteractionDisabled else { return }

                if !didCrossThreshold,
                   PracticeSwipeInteraction.crossedDistanceThreshold(
                       previousTranslation: previousTranslation,
                       currentTranslation: value.translation,
                       cardWidth: cardWidth
                   ) {
                    didCrossThreshold = true
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                previousTranslation = value.translation
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard !isInteractionDisabled else { return }
                let action = PracticeSwipeInteraction.action(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    cardWidth: cardWidth
                )
                didCrossThreshold = false
                previousTranslation = .zero
                if let action, action != .delete || canDelete {
                    commit(action)
                } else {
                    resetDrag()
                }
            }
    }

    private func commit(_ action: PracticeSwipeAction) {
        guard !isInteractionDisabled,
              action != .delete || canDelete
        else { return }

        let exitOffset: CGSize
        switch action {
        case .skip:
            exitOffset = CGSize(width: -(cardWidth + 160), height: 0)
        case .answer:
            exitOffset = CGSize(width: cardWidth + 160, height: 0)
        case .delete:
            exitOffset = CGSize(width: 0, height: -(cardWidth + 160))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22),
            completionCriteria: .logicallyComplete
        ) {
            dragTranslation = exitOffset
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragTranslation = .zero
            }
            onCommit(action)
        }
    }

    private func resetDrag() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            dragTranslation = .zero
        }
    }

    private func indicatorOpacity(for action: PracticeSwipeAction) -> Double {
        let isMatchingDirection: Bool
        switch action {
        case .skip:
            isMatchingDirection = dragTranslation.width < 0
                && abs(dragTranslation.width) >= abs(dragTranslation.height)
        case .answer:
            isMatchingDirection = dragTranslation.width > 0
                && abs(dragTranslation.width) >= abs(dragTranslation.height)
        case .delete:
            isMatchingDirection = dragTranslation.height < 0
                && abs(dragTranslation.height) > abs(dragTranslation.width)
        }
        guard isMatchingDirection else { return 0 }
        let threshold = cardWidth * PracticeSwipeInteraction.distanceThresholdRatio
        let distance = action == .delete
            ? abs(dragTranslation.height)
            : abs(dragTranslation.width)
        return Double(min(distance / max(threshold, 1), 1))
    }

    private func swipeIndicator(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.heavy))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .foregroundStyle(color)
            .background(Color(uiColor: .systemBackground).opacity(0.96), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(color, lineWidth: 2.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}
