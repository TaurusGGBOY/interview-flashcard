import SwiftUI
import UIKit

struct PracticeFeedView: View {
    let card: QuestionCardSnapshot?
    let emptyReason: PracticeFeedEmptyReason?
    let isAnswering: Bool
    let isInteractionDisabled: Bool
    let undoTitle: String?
    let onSkip: () -> Void
    let onDelete: () -> Void
    let onStartAnswer: () -> Void
    let onReturnToQuestion: () -> Void
    let onViewHistory: () -> Void
    let onAttemptSubmitted: (UUID) -> Void
    let onContinueSession: () -> Void
    let onUndo: () -> Void
    let onOpenLibrary: () -> Void

    var body: some View {
        Group {
            if let card {
                cardFeed(card)
            } else {
                emptyFeed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(PracticeAccessibilityID.screen)
    }

    @ViewBuilder
    private func cardFeed(_ card: QuestionCardSnapshot) -> some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                PracticeSwipeActionLayer(
                    cardWidth: max(proxy.size.width, 1),
                    cardHeight: max(proxy.size.height, 1),
                    isInteractionDisabled: isInteractionDisabled,
                    skipTitle: isAnswering ? "返回题目" : "跳过",
                    skipSystemImage: isAnswering ? "arrow.left" : "xmark",
                    answerTitle: isAnswering ? "查看历史" : "开始回答",
                    answerSystemImage: isAnswering ? "clock.arrow.circlepath" : "pencil.and.outline",
                    canDelete: !isAnswering,
                    onCommit: { action in
                        switch action {
                        case .skip:
                            if isAnswering { onReturnToQuestion() } else { onSkip() }
                        case .answer:
                            if isAnswering { onViewHistory() } else { onStartAnswer() }
                        case .delete:
                            if !isAnswering { onDelete() }
                        }
                    }
                ) {
                    ZStack {
                        if isAnswering {
                            ZStack {
                                AnswerEditorView(
                                    questionID: card.id,
                                    presentation: .cardBack,
                                    onAttemptSubmitted: onAttemptSubmitted,
                                    onContinueSession: onContinueSession
                                )
                                .id(card.id)
                                .accessibilityIdentifier(PracticeAccessibilityID.cardBack)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                            .accessibilityIdentifier(PracticeAccessibilityID.cardBackSurface)
                        } else {
                            QuestionCardView(card: card)
                        }
                    }
                    .rotation3DEffect(
                        .degrees(isAnswering ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .animation(.easeInOut(duration: 0.42), value: isAnswering)
                }
            }
            .frame(minHeight: 420, maxHeight: .infinity)

            Text(isAnswering ? "左滑返回题目 · 右滑查看历史" : "左滑跳过 · 右滑开始回答 · 上划删除本题")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(PracticeAccessibilityID.swipeHint)

            HStack(spacing: 12) {
                Button {
                    if isAnswering { onReturnToQuestion() } else { onSkip() }
                } label: {
                    Label(isAnswering ? "返回题目" : "跳过", systemImage: isAnswering ? "arrow.left" : "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(minHeight: 48)
                .disabled(isInteractionDisabled)
                .accessibilityIdentifier(isAnswering ? PracticeAccessibilityID.returnToQuestion : PracticeAccessibilityID.skip)

                Button {
                    if isAnswering { onViewHistory() } else { onStartAnswer() }
                } label: {
                    Label(isAnswering ? "查看历史" : "开始回答", systemImage: isAnswering ? "clock.arrow.circlepath" : "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(minHeight: 48)
                .disabled(isInteractionDisabled)
                .accessibilityIdentifier(isAnswering ? PracticeAccessibilityID.viewHistory : PracticeAccessibilityID.answer)
            }

            if let undoTitle {
                Button(undoTitle, action: onUndo)
                    .buttonStyle(.borderless)
                    .disabled(isInteractionDisabled)
                    .accessibilityIdentifier(PracticeAccessibilityID.undo)
            }
        }
        .safeAreaPadding(.horizontal, 18)
        .safeAreaPadding(.vertical, 12)
    }

    @ViewBuilder
    private var emptyFeed: some View {
        VStack(spacing: 12) {
            switch emptyReason {
            case .globalLibraryEmpty:
                ContentUnavailableView {
                    Label("题库还是空的", systemImage: "books.vertical")
                } description: {
                    Text("先导入一份 Markdown 题库，再开始练习。")
                } actions: {
                    Button("去题库导入", action: onOpenLibrary)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(PracticeAccessibilityID.emptyLibrary)
                }
            case .noTopicsSelected:
                ContentUnavailableView {
                    Label("尚未选择练习主题", systemImage: "checklist")
                } description: {
                    Text("请前往“设置 → 练习设置”选择至少一个主题。")
                }
            case .filteredPoolEmpty:
                ContentUnavailableView {
                    Label("当前设置没有可练习题", systemImage: "rectangle.stack.badge.minus")
                } description: {
                    Text("可在“设置 → 练习设置”更换主题或开启“包含已练习题”。")
                }
            case nil:
                ProgressView("正在准备题目…")
            }

            if let undoTitle {
                Button(undoTitle, action: onUndo)
                    .buttonStyle(.borderless)
                    .disabled(isInteractionDisabled)
                    .accessibilityIdentifier(PracticeAccessibilityID.undo)
            }
        }
    }
}
