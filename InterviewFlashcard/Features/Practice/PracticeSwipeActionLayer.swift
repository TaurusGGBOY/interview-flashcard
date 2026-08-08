import SwiftUI
import UIKit

struct PracticeSwipeActionLayer<Content: View>: View {
    let cardWidth: CGFloat
    let isInteractionDisabled: Bool
    let onCommit: (PracticeSwipeAction) -> Void
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragTranslation: CGSize = .zero
    @State private var previousTranslation: CGSize = .zero
    @State private var didCrossThreshold = false

    init(
        cardWidth: CGFloat,
        isInteractionDisabled: Bool,
        onCommit: @escaping (PracticeSwipeAction) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cardWidth = cardWidth
        self.isInteractionDisabled = isInteractionDisabled
        self.onCommit = onCommit
        self.content = content()
    }

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                swipeIndicator(title: "开始回答", systemImage: "pencil.and.outline", color: .green)
                    .padding(24)
                    .opacity(indicatorOpacity(for: .answer))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(PracticeAccessibilityID.answerIndicator)
            }
            .overlay(alignment: .topTrailing) {
                swipeIndicator(title: "跳过", systemImage: "xmark", color: .red)
                    .padding(24)
                    .opacity(indicatorOpacity(for: .skip))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier(PracticeAccessibilityID.skipIndicator)
            }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .offset(x: dragTranslation.width)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragTranslation.width / max(cardWidth, 1)) * 7))
            .simultaneousGesture(dragGesture)
            .allowsHitTesting(!isInteractionDisabled)
            .accessibilityAction(named: "跳过") {
                commit(.skip)
            }
            .accessibilityAction(named: "开始回答") {
                commit(.answer)
            }
            .onChange(of: cardWidth) { _, _ in
                dragTranslation = .zero
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isInteractionDisabled else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

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
                dragTranslation = CGSize(width: value.translation.width, height: 0)
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
                if let action {
                    commit(action)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dragTranslation = .zero
                    }
                }
            }
    }

    private func commit(_ action: PracticeSwipeAction) {
        guard !isInteractionDisabled else { return }
        let exitOffset = action == .skip ? -(cardWidth + 160) : cardWidth + 160
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(
            reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22),
            completionCriteria: .logicallyComplete
        ) {
            dragTranslation = CGSize(width: exitOffset, height: 0)
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragTranslation = .zero
            }
            onCommit(action)
        }
    }

    private func indicatorOpacity(for action: PracticeSwipeAction) -> Double {
        let isMatchingDirection = (action == .skip && dragTranslation.width < 0)
            || (action == .answer && dragTranslation.width > 0)
        guard isMatchingDirection else { return 0 }
        let threshold = cardWidth * PracticeSwipeInteraction.distanceThresholdRatio
        return Double(min(abs(dragTranslation.width) / max(threshold, 1), 1))
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
