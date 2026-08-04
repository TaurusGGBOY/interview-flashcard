import SwiftData
import SwiftUI

enum AnswerEditorAccessibilityID {
    static let screen = "answer-editor.screen"
    static let textEditor = "answer-editor.text"
    static let submit = "answer-editor.submit"
    static let voice = "answer-editor.voice"
    static let processing = "answer-editor.processing"
    static let failure = "answer-editor.failure"
    static let result = "answer-editor.result"
}

@MainActor
struct AnswerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var environment
    @Query private var cards: [QuestionCardRecord]

    private let questionID: UUID
    @State private var answerText = ""
    @State private var isShowingVoice = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var submittedAttemptID: UUID?
    @State private var processingResult: EvaluationRecord?

    init(questionID: UUID) {
        self.questionID = questionID
        _cards = Query(filter: #Predicate<QuestionCardRecord> { card in card.id == questionID })
    }

    private var card: QuestionCardRecord? { cards.first }

    var body: some View {
        Form {
            if let card {
                Section("题目") {
                    Text(card.questionText)
                        .font(.headline)
                    Text("回答后会先由 AI 润色，再按六个维度评分。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("文字回答") {
                    TextEditor(text: $answerText)
                        .frame(minHeight: 190)
                        .accessibilityIdentifier(AnswerEditorAccessibilityID.textEditor)
                    Button {
                        submitText()
                    } label: {
                        Label("提交文字回答", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.submit)
                }

                Section("语音回答") {
                    Button {
                        isShowingVoice = true
                    } label: {
                        Label("录音并本地转写", systemImage: "mic.fill")
                    }
                    .disabled(isProcessing || !speechCapabilityAllowsVoice)
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.voice)
                    if !speechCapabilityAllowsVoice {
                        Text("当前设备无法本地转写，因此语音按钮已禁用。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("题目不存在", systemImage: "questionmark.folder")
            }

            if isProcessing {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在润色并评分…")
                    }
                    .accessibilityIdentifier(AnswerEditorAccessibilityID.processing)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AnswerEditorAccessibilityID.failure)
                    if let attemptID = submittedAttemptID {
                        Button("重试评分") { process(attemptID: attemptID) }
                            .disabled(isProcessing)
                    }
                }
            }

            if let processingResult {
                Section("本次评分") {
                    if let total = processingResult.totalScore {
                        LabeledContent("总分", value: "\(total) / 100")
                            .accessibilityIdentifier(AnswerEditorAccessibilityID.result)
                    } else {
                        Text("回答内容不足，暂不可评分。")
                            .accessibilityIdentifier(AnswerEditorAccessibilityID.result)
                    }
                    ForEach(ScoreDimension.allCases, id: \.self) { dimension in
                        LabeledContent(dimension.displayName, value: "\(processingResult.dimensionScores[dimension])")
                    }
                    if let card, let reference = card.referenceAnswers.max(by: { $0.version < $1.version }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("满分答案（v\(reference.version)）")
                                .font(.headline)
                            Text(reference.answerText)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("回答")
        .accessibilityIdentifier(AnswerEditorAccessibilityID.screen)
        .sheet(isPresented: $isShowingVoice) {
            if let card {
                VoiceAnswerView(
                    questionID: card.id,
                    transcriber: environment.resolvedSpeechTranscriber,
                    audioRecorder: environment.makeResolvedAudioRecorder(),
                    submissionService: AnswerSubmissionService(
                        now: environment.dependencies.now,
                        diagnosticExporter: DiagnosticStateExporter(isEnabled: environment.launchOptions.diagnosticsEnabled)
                    ),
                    onSubmitted: { attempt in
                        processingResult = nil
                        submittedAttemptID = attempt.id
                        process(attemptID: attempt.id)
                    }
                )
            }
        }
    }

    private var speechCapabilityAllowsVoice: Bool {
        switch environment.launchOptions.speechCapability {
        case .unsupported, .denied, .permissionDenied:
            false
        case .automatic, .supported, .fixtureSupported:
            true
        }
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
            submittedAttemptID = attempt.id
            process(attemptID: attempt.id)
        } catch {
            errorMessage = error.localizedDescription
        }
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
