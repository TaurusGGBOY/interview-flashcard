import SwiftUI

struct EvaluationResultView: View {
    let evaluation: EvaluationRecord
    let onContinue: () -> Void
    let onClose: (() -> Void)?
    let onRescore: (() -> Void)?
    let isRescoring: Bool
    let continueTitle: String
    let continueSystemImage: String

    @State private var isShowingHistory = false

    init(
        evaluation: EvaluationRecord,
        onContinue: @escaping () -> Void,
        onClose: (() -> Void)? = nil,
        onRescore: (() -> Void)? = nil,
        isRescoring: Bool = false,
        continueTitle: String = "下一题",
        continueSystemImage: String = "arrow.right"
    ) {
        self.evaluation = evaluation
        self.onContinue = onContinue
        self.onClose = onClose
        self.onRescore = onRescore
        self.isRescoring = isRescoring
        self.continueTitle = continueTitle
        self.continueSystemImage = continueSystemImage
    }

    private var presentation: EvaluationPresentation {
        EvaluationPresentation(evaluation: evaluation)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scoreHeader
                stageStatus
                ScoreRadarChart(dimensions: presentation.dimensions)
                dimensions
                answerComparison
                feedbackSections
                Button {
                    isShowingHistory = true
                } label: {
                    Label("查看这道题的回答历史", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("answer-editor.result.history")

                if let onRescore {
                    Button {
                        onRescore()
                    } label: {
                        Group {
                            if isRescoring {
                                Label("正在重新评分…", systemImage: "hourglass")
                            } else {
                                Label("重新评分", systemImage: "arrow.clockwise")
                            }
                        }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRescoring)
                    .accessibilityIdentifier("answer-editor.result.rescore")
                }

                Button {
                    onContinue()
                } label: {
                    Label(continueTitle, systemImage: continueSystemImage)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AnswerEditorAccessibilityID.continueSession)
            }
            .safeAreaPadding(.horizontal, 20)
            .safeAreaPadding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("本次结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") {
                        onClose()
                    }
                    .accessibilityIdentifier("answer-editor.result.close")
                }
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            QuestionHistoryView(question: evaluation.attempt.question)
        }
        .accessibilityIdentifier(AnswerEditorAccessibilityID.result)
    }

    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("回答已保存")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let totalScore = presentation.totalScore {
                Text("\(totalScore)")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(scoreColor(totalScore))
                Text("/ 100 综合得分")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂不可评分")
                    .font(.title2.weight(.bold))
                Text("回答已保存，可稍后重试评分。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier(AnswerEditorAccessibilityID.resultScore)
    }

    @ViewBuilder
    private var stageStatus: some View {
        switch (evaluation.status, evaluation.attempt.processingStatus) {
        case (.feedback, _):
            stageBanner(
                title: "分数已出",
                message: "正在生成每个小项的评语，分数不会改变。",
                systemImage: "text.bubble"
            )
        case (.completed, .referenceAnswer):
            stageBanner(
                title: "评语已出",
                message: "正在生成满分答案，完成后会自动显示。",
                systemImage: "sparkles"
            )
        case (.failed, _), (_, .failed):
            if let failure = evaluation.attempt.failureSummary {
                stageBanner(title: "补充内容生成失败", message: failure, systemImage: "exclamationmark.triangle")
            }
        default:
            EmptyView()
        }
    }

    private func stageBanner(title: String, message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if evaluation.status == .feedback || evaluation.attempt.processingStatus == .referenceAnswer {
                ProgressView()
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("answer-editor.result.stage")
    }

    private var dimensions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("六维具体详情")
                .font(.headline)
            ForEach(Array(presentation.dimensions.enumerated()), id: \.element.dimension.rawValue) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.dimension.displayName)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 12)
                        Text("\(row.score)/100")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    ProgressView(value: Double(row.score), total: 100)
                        .tint(scoreColor(row.score))
                    Text(row.feedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                }
                if index < presentation.dimensions.count - 1 { Divider() }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(PracticeAccessibilityID.details)
    }

    @ViewBuilder
    private var feedbackSections: some View {
        if !presentation.strengths.isEmpty {
            feedbackList(title: "做得好的地方", icon: "checkmark.circle.fill", color: .green, items: presentation.strengths)
        }
        if !presentation.weaknesses.isEmpty {
            feedbackList(title: "做得不好的地方", icon: "exclamationmark.circle.fill", color: .orange, items: presentation.weaknesses)
        }
    }

    private func feedbackList(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: "circle.fill")
                    .font(.subheadline)
                    .labelStyle(FeedbackLabelStyle())
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var answerComparison: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("回答对照")
                .font(.headline)
            answerBlock(title: "原始回答", text: presentation.rawText, tint: .blue)
            if let polishedText = presentation.polishedText {
                answerBlock(title: "历史润色版本", text: polishedText, tint: .purple)
            }
            VStack(alignment: .leading, spacing: 6) {
                if presentation.referenceAnswer.isEmpty {
                    Label("满分答案生成中…", systemImage: "hourglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("满分答案（v\(presentation.referenceVersion)）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(presentation.referenceAnswer)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("answer-editor.result.reference-answer")
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.green.opacity(0.28), lineWidth: 1)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func answerBlock(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: .green
        case 60..<80: .orange
        default: .red
        }
    }
}

private struct FeedbackLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
