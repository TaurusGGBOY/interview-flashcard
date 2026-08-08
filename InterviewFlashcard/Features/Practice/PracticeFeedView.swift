import SwiftUI
import UIKit

struct PracticeFeedView: View {
    let card: QuestionCardSnapshot?
    let emptyReason: PracticeFeedEmptyReason?
    let isInteractionDisabled: Bool
    let canUndo: Bool
    let onSkip: () -> Void
    let onStartAnswer: () -> Void
    let onUndo: () -> Void
    let onOpenFilter: () -> Void
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
    }

    @ViewBuilder
    private func cardFeed(_ card: QuestionCardSnapshot) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Label("随机练习", systemImage: "rectangle.stack.fill")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: onOpenFilter) {
                    Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .accessibilityLabel("筛选")
                .accessibilityIdentifier(PracticeAccessibilityID.filter)
            }
            .frame(minHeight: 44)

            GeometryReader { proxy in
                PracticeSwipeActionLayer(
                    cardWidth: max(proxy.size.width, 1),
                    isInteractionDisabled: isInteractionDisabled,
                    onCommit: { action in
                        switch action {
                        case .skip: onSkip()
                        case .answer: onStartAnswer()
                        }
                    }
                ) {
                    QuestionCardView(card: card)
                }
            }
            .frame(minHeight: 340)

            Text("左滑跳过 · 右滑开始回答")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(PracticeAccessibilityID.swipeHint)

            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Label("跳过", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(minHeight: 48)
                .disabled(isInteractionDisabled)
                .accessibilityIdentifier(PracticeAccessibilityID.skip)

                Button(action: onStartAnswer) {
                    Label("开始回答", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(minHeight: 48)
                .disabled(isInteractionDisabled)
                .accessibilityIdentifier(PracticeAccessibilityID.answer)
            }

            if canUndo {
                Button("撤销跳过", action: onUndo)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(PracticeAccessibilityID.undo)
            }
        }
        .safeAreaPadding(.horizontal, 18)
        .safeAreaPadding(.vertical, 12)
        .accessibilityIdentifier(PracticeAccessibilityID.screen)
    }

    @ViewBuilder
    private var emptyFeed: some View {
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
        case .filteredPoolEmpty:
            ContentUnavailableView {
                Label("当前筛选没有题目", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("可以调整 Topic，或开启“包含已练习题”。")
            } actions: {
                Button("调整筛选", action: onOpenFilter)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(PracticeAccessibilityID.emptyFilter)
            }
        case nil:
            ProgressView("正在准备题目…")
        }
    }
}
