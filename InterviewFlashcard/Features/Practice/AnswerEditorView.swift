import SwiftData
import SwiftUI

enum AnswerEditorAccessibilityID {
    static let screen = "answer-editor.screen"
    static let question = "answer-editor.question"
    static let textEditor = "answer-editor.text"
    static let submit = "answer-editor.submit"
    static let processing = "answer-editor.processing"
    static let failure = "answer-editor.failure"
    static let result = "answer-editor.result"
    static let resultScore = "answer-editor.result.score"
    static let continueSession = "answer-editor.continue"
    static let nextWhileProcessing = "answer-editor.next-while-processing"
}

@MainActor
struct AnswerEditorView: View {
    enum Presentation {
        case screen
        case cardBack
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query private var cards: [QuestionCardRecord]
    @Query(sort: \AnswerAttemptRecord.submittedAt, order: .reverse) private var attempts: [AnswerAttemptRecord]
    @Query(sort: \EvaluationRecord.createdAt, order: .reverse) private var evaluations: [EvaluationRecord]

    private let questionID: UUID
    private let presentation: Presentation
    private let onAttemptSubmitted: (UUID) -> Void
    private let onContinueSession: () -> Void

    @State private var answerText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var submittedAttemptID: UUID?
    @State private var processingResult: EvaluationRecord?
    @State private var isShowingResult = false

    private struct AttemptProgress: Equatable {
        let attemptID: UUID
        let processingStatusRaw: String
        let evaluationID: UUID?
        let evaluationStatusRaw: String?
        let failureSummary: String?
    }

    init(
        questionID: UUID,
        presentation: Presentation = .screen,
        onAttemptSubmitted: @escaping (UUID) -> Void = { _ in },
        onContinueSession: @escaping () -> Void = {}
    ) {
        self.questionID = questionID
        self.presentation = presentation
        self.onAttemptSubmitted = onAttemptSubmitted
        self.onContinueSession = onContinueSession
        _cards = Query(filter: #Predicate<QuestionCardRecord> { card in card.id == questionID })
    }

    nonisolated static func submittedQuestionID(questionID: UUID, attemptID: UUID) -> UUID {
        questionID
    }

    nonisolated static func navigationTitle(for presentation: Presentation) -> String {
        presentation == .screen ? "回答" : ""
    }

    private var card: QuestionCardRecord? { cards.first }

    var body: some View {
        ScrollView {
            editorContent
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            if presentation == .cardBack {
                Color(uiColor: .systemBackground)
            } else {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(Self.navigationTitle(for: presentation))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .screen {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") {
                        dismiss()
                    }
                    .accessibilityIdentifier("answer-editor.close")
                }
            }
        }
        .accessibilityIdentifier(AnswerEditorAccessibilityID.screen)
        .onChange(of: submittedAttemptProgress, initial: true) { _, _ in
            revealCompletedEvaluationIfNeeded()
        }
        .sheet(isPresented: $isShowingResult) {
            if let processingResult {
                NavigationStack {
                    EvaluationResultView(
                        evaluation: processingResult,
                        onContinue: continueFromResult,
                        onClose: { isShowingResult = false },
                        onRescore: rescoreCurrentAttempt
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let card {
                questionHeader(card)
                AnswerComposerView(
                    text: $answerText,
                    isSubmitting: isProcessing,
                    onSubmit: submitText
                )
            } else {
                ContentUnavailableView("题目不存在", systemImage: "questionmark.folder")
            }

            processingStatus
            failureStatus
            pendingNavigation
        }
        .safeAreaPadding(.horizontal, 20)
        .safeAreaPadding(.vertical, 16)
    }

    private func questionHeader(_ card: QuestionCardRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("面试题", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Text(card.topic.systemKind == .others ? "待分类" : card.topic.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(card.questionText)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AnswerEditorAccessibilityID.question)
            Text("提交后先显示分数，再依次补充评语和满分答案。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var processingStatus: some View {
        if isProcessing {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在后台评分…")
                        .font(.subheadline.weight(.medium))
                    Text("可以继续下一题，稍后也可在历史中查看结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier(AnswerEditorAccessibilityID.processing)
        }
    }

    @ViewBuilder
    private var pendingNavigation: some View {
        if submittedAttemptID != nil, !isShowingResult {
            Button(
                presentation == .cardBack ? "下一题" : "关闭",
                systemImage: presentation == .cardBack ? "arrow.right" : "xmark",
                action: continueAfterSubmit
            )
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(AnswerEditorAccessibilityID.nextWhileProcessing)
        }
    }

    @ViewBuilder
    private var failureStatus: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.failure)
                if let attemptID = submittedAttemptID {
                    Button("重试评分") { process(attemptID: attemptID) }
                        .disabled(isProcessing)
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func submitText() {
        guard card != nil, !isProcessing else { return }

        processingResult = nil
        errorMessage = nil
        isProcessing = true
        Task { @MainActor in
            guard let card else {
                errorMessage = "题目已不存在，请返回题库重新选择。"
                isProcessing = false
                return
            }

            do {
                let submissionService = AnswerSubmissionService(
                    now: environment.dependencies.now,
                    diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
                )
                let attempt = try submissionService.submitText(
                    questionID: card.id,
                    rawText: answerText,
                    context: modelContext
                )
                answerText = ""
                acceptSubmittedAttempt(attempt)
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func acceptSubmittedAttempt(_ attempt: AnswerAttemptRecord) {
        submittedAttemptID = attempt.id
        processingResult = nil
        onAttemptSubmitted(
            Self.submittedQuestionID(questionID: questionID, attemptID: attempt.id)
        )
        if !environment.scheduleAnswerProcessing(attemptID: attempt.id) {
            // Test hosts and previews may not install AppRuntime's scheduler.
            // Keep those contexts functional with the original local fallback.
            process(attemptID: attempt.id)
        }
    }

    private var submittedAttemptProgress: AttemptProgress? {
        guard let submittedAttemptID,
              let attempt = attempts.first(where: { $0.id == submittedAttemptID })
        else {
            return nil
        }
        let evaluation = latestEvaluation(for: attempt.id)
        return AttemptProgress(
            attemptID: attempt.id,
            processingStatusRaw: attempt.processingStatusRaw,
            evaluationID: evaluation?.id,
            evaluationStatusRaw: evaluation?.statusRaw,
            failureSummary: attempt.failureSummary
        )
    }

    private func revealCompletedEvaluationIfNeeded() {
        guard let submittedAttemptID,
              let attempt = attempts.first(where: { $0.id == submittedAttemptID })
        else {
            return
        }

        if attempt.processingStatus == .failed {
            isProcessing = false
            if errorMessage == nil {
                errorMessage = attempt.failureSummary ?? "评分失败，请重试。"
            }
            return
        }

        guard let evaluation = latestEvaluation(for: attempt.id),
              evaluation.status == .feedback || evaluation.status == .completed
        else {
            return
        }

        isProcessing = false
        guard processingResult?.id != evaluation.id else { return }
        processingResult = evaluation
        isShowingResult = true
    }

    private func latestEvaluation(for attemptID: UUID) -> EvaluationRecord? {
        evaluations.first(where: { $0.attempt.id == attemptID })
    }

    private func continueAfterSubmit() {
        isShowingResult = false
        processingResult = nil
        if presentation == .cardBack {
            onContinueSession()
        } else {
            dismiss()
        }
    }

    private func process(attemptID: UUID, forceRescore: Bool = false) {
        isProcessing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let service = AnswerProcessingService(
                    aiClient: environment.dependencies.aiClient,
                    now: environment.dependencies.now,
                    diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
                )
                let evaluation = try await service.score(
                    attemptID: attemptID,
                    context: modelContext,
                    forceRescore: forceRescore
                )
                // Publish the numeric result immediately. The following two
                // requests intentionally continue after the result page is
                // visible.
                processingResult = evaluation
                isShowingResult = true
                isProcessing = false
                guard evaluation.status == .feedback else { return }
                do {
                    try await service.completeFeedback(
                        attemptID: attemptID,
                        evaluationID: evaluation.id,
                        context: modelContext
                    )
                    _ = try await service.prepareReferenceAnswer(
                        attemptID: attemptID,
                        context: modelContext
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func continueFromResult() {
        isShowingResult = false
        onContinueSession()
        if presentation == .screen {
            dismiss()
        }
    }

    private func rescoreCurrentAttempt() {
        guard let attemptID = submittedAttemptID, !isProcessing else { return }
        isShowingResult = false
        processingResult = nil
        process(attemptID: attemptID, forceRescore: true)
    }
}
