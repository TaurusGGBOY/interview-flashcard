import SwiftData
import SwiftUI

enum AnswerEditorAccessibilityID {
    static let screen = "answer-editor.screen"
    static let question = "answer-editor.question"
    static let textEditor = "answer-editor.text"
    static let submit = "answer-editor.submit"
    static let voice = "answer-editor.voice"
    static let processing = "answer-editor.processing"
    static let failure = "answer-editor.failure"
    static let result = "answer-editor.result"
    static let resultScore = "answer-editor.result.score"
    static let continueSession = "answer-editor.continue"
}

@MainActor
struct AnswerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query private var cards: [QuestionCardRecord]

    private let questionID: UUID
    private let onAttemptSubmitted: (UUID) -> Void
    private let onContinueSession: () -> Void

    @State private var answerText = ""
    @State private var isShowingVoice = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var submittedAttemptID: UUID?
    @State private var processingResult: EvaluationRecord?
    @State private var localSpeechCapability: LocalSpeechCapability = .unavailable(.recognizerUnavailable)

    init(
        questionID: UUID,
        onAttemptSubmitted: @escaping (UUID) -> Void = { _ in },
        onContinueSession: @escaping () -> Void = {}
    ) {
        self.questionID = questionID
        self.onAttemptSubmitted = onAttemptSubmitted
        self.onContinueSession = onContinueSession
        _cards = Query(filter: #Predicate<QuestionCardRecord> { card in card.id == questionID })
    }

    nonisolated static func submittedQuestionID(questionID: UUID, attemptID: UUID) -> UUID {
        questionID
    }

    private var card: QuestionCardRecord? { cards.first }

    var body: some View {
        Group {
            if let processingResult {
                EvaluationResultView(evaluation: processingResult) {
                    onContinueSession()
                    dismiss()
                }
            } else {
                ScrollView {
                    editorContent
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("回答")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AnswerEditorAccessibilityID.screen)
        .task {
            localSpeechCapability = await environment.resolvedSpeechTranscriber.localCapability(
                locale: Locale(identifier: "zh-CN")
            )
        }
        .sheet(isPresented: $isShowingVoice) {
            if let card, speechCapabilityAllowsVoice {
                VoiceAnswerView(
                    questionID: card.id,
                    transcriber: environment.resolvedSpeechTranscriber,
                    audioRecorder: environment.makeResolvedAudioRecorder(),
                    submissionService: AnswerSubmissionService(
                        now: environment.dependencies.now,
                        diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
                    ),
                    onSubmitted: acceptSubmittedAttempt
                )
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
                voiceEntry
            } else {
                ContentUnavailableView("题目不存在", systemImage: "questionmark.folder")
            }

            processingStatus
            failureStatus
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
            Text("先独立回答；提交后才会显示 AI 六维评分和满分答案。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var voiceEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语音回答")
                .font(.headline)
            if speechCapabilityAllowsVoice {
                Button {
                    isShowingVoice = true
                } label: {
                    Label("录音并本地转写", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
                .accessibilityIdentifier(AnswerEditorAccessibilityID.voice)
            } else {
                Label("本机无法本地转写", systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.voice)
                Text("语音入口会在设备端转写能力可用时出现；当前仍可使用文字回答。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var processingStatus: some View {
        if isProcessing {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在评分…")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier(AnswerEditorAccessibilityID.processing)
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

    private var speechCapabilityAllowsVoice: Bool {
        localSpeechCapability.canStartVoiceAnswer
    }

    private func submitText() {
        guard let card else { return }
        do {
            processingResult = nil
            let attempt = try AnswerSubmissionService(
                now: environment.dependencies.now,
                diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
            ).submitText(questionID: card.id, rawText: answerText, context: modelContext)
            answerText = ""
            acceptSubmittedAttempt(attempt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptSubmittedAttempt(_ attempt: AnswerAttemptRecord) {
        submittedAttemptID = attempt.id
        processingResult = nil
        onAttemptSubmitted(
            Self.submittedQuestionID(questionID: questionID, attemptID: attempt.id)
        )
        process(attemptID: attempt.id)
    }

    private func process(attemptID: UUID) {
        isProcessing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                processingResult = try await AnswerProcessingService(
                    aiClient: environment.dependencies.aiClient,
                    now: environment.dependencies.now,
                    diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
                ).process(attemptID: attemptID, context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
