import Foundation
import Observation
import SwiftData
import SwiftUI

private enum VoiceAnswerAccessibilityID {
    static let screen = "voice-answer.screen"
    static let record = "voice-answer.record"
    static let stop = "voice-answer.stop"
    static let unavailable = "voice-answer.unavailable"
    static let transcript = "voice-answer.transcript"
    static let confirm = "voice-answer.confirm"
    static let cancel = "voice-answer.cancel"
}

@MainActor
@Observable
final class VoiceAnswerController {
    enum Phase: Sendable, Equatable {
        case checkingCapability
        case ready
        case recording
        case transcribing
        case confirmation
        case unavailable
        case failed
        case cancelled
    }

    private(set) var phase: Phase = .checkingCapability
    private(set) var capability: LocalSpeechCapability?
    private(set) var recordedAudio: RecordedAudio?
    private(set) var transcriptResult: SpeechTranscript?
    var transcriptText = ""
    private(set) var errorMessage: String?

    private let transcriber: any SpeechTranscribing
    private let audioRecorder: any AudioRecording
    private let locale: Locale

    init(
        transcriber: any SpeechTranscribing,
        audioRecorder: any AudioRecording,
        locale: Locale
    ) {
        self.transcriber = transcriber
        self.audioRecorder = audioRecorder
        self.locale = locale
    }

    func refreshCapability() async {
        phase = .checkingCapability
        errorMessage = nil
        let capability = await transcriber.localCapability(locale: locale)
        self.capability = capability
        phase = capability.canStartVoiceAnswer ? .ready : .unavailable
        if case let .unavailable(reason) = capability {
            errorMessage = reason.userMessage
        }
    }

    func startRecording() async {
        guard capability?.canStartVoiceAnswer == true else {
            phase = .unavailable
            errorMessage = "当前设备无法本地转写。"
            return
        }
        do {
            _ = try await audioRecorder.start()
            phase = .recording
            errorMessage = nil
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    func stopAndTranscribe() async {
        guard phase == .recording else { return }
        do {
            let audio = try await audioRecorder.stop()
            recordedAudio = audio
            phase = .transcribing
            let transcript = try await transcriber.transcribe(
                fileURL: audio.fileURL,
                locale: locale
            )
            let normalizedText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else {
                throw SpeechTranscriptionError.emptyTranscript
            }
            transcriptResult = transcript
            transcriptText = normalizedText
            phase = .confirmation
            errorMessage = nil
        } catch let error as SpeechTranscriptionError {
            if case let .unavailable(reason) = error {
                capability = .unavailable(reason)
                phase = .unavailable
            } else {
                phase = .failed
            }
            errorMessage = error.localizedDescription
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    func audioAssetDraft() throws -> AnswerSubmissionService.AudioAssetDraft {
        let confirmedText = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmedText.isEmpty else { throw SpeechTranscriptionError.emptyTranscript }
        guard let recordedAudio, let transcriptResult else {
            throw AnswerSubmissionService.SubmissionError.missingAudioAsset
        }
        return AnswerSubmissionService.AudioAssetDraft(
            relativePath: recordedAudio.relativePath,
            format: recordedAudio.format,
            duration: recordedAudio.duration,
            byteCount: recordedAudio.byteCount,
            checksum: recordedAudio.checksum,
            transcriptionEngine: transcriptResult.engine,
            localeIdentifier: transcriptResult.localeIdentifier,
            confidenceSummary: transcriptResult.confidenceSummary
        )
    }

    func cancel() async {
        await audioRecorder.cancel()
        recordedAudio = nil
        transcriptResult = nil
        transcriptText = ""
        phase = .cancelled
    }
}

@MainActor
struct VoiceAnswerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var controller: VoiceAnswerController
    @State private var submissionError: String?

    private let questionID: UUID
    private let submissionService: AnswerSubmissionService
    private let onSubmitted: (AnswerAttemptRecord) -> Void

    init(
        questionID: UUID,
        transcriber: any SpeechTranscribing,
        audioRecorder: any AudioRecording,
        locale: Locale = Locale(identifier: "zh-CN"),
        submissionService: AnswerSubmissionService,
        onSubmitted: @escaping (AnswerAttemptRecord) -> Void = { _ in }
    ) {
        self.questionID = questionID
        self.submissionService = submissionService
        self.onSubmitted = onSubmitted
        _controller = State(
            initialValue: VoiceAnswerController(
                transcriber: transcriber,
                audioRecorder: audioRecorder,
                locale: locale
            )
        )
    }

    var body: some View {
        Form {
            Section {
                phaseContent
            } header: {
                Text("语音回答")
            } footer: {
                Text("录音和转写都只在本机处理，音频不会发送给 AI。")
            }

            if let message = submissionError ?? controller.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("错误：\(message)")
                }
            }

            Section {
                Button("取消", role: .cancel) {
                    Task {
                        await controller.cancel()
                        dismiss()
                    }
                }
                .accessibilityIdentifier(VoiceAnswerAccessibilityID.cancel)
            }
        }
        .navigationTitle("录制回答")
        .accessibilityIdentifier(VoiceAnswerAccessibilityID.screen)
        .task {
            guard controller.phase == .checkingCapability else { return }
            await controller.refreshCapability()
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .checkingCapability:
            HStack {
                ProgressView()
                Text("正在检查本地转写能力…")
            }
        case .ready:
            Button {
                Task { await controller.startRecording() }
            } label: {
                Label("开始录音", systemImage: "mic.fill")
            }
            .accessibilityIdentifier(VoiceAnswerAccessibilityID.record)
        case .recording:
            Button {
                Task { await controller.stopAndTranscribe() }
            } label: {
                Label("停止并本地转写", systemImage: "stop.fill")
            }
            .tint(.red)
            .accessibilityIdentifier(VoiceAnswerAccessibilityID.stop)
        case .transcribing:
            HStack {
                ProgressView()
                Text("正在本地转写…")
            }
        case .confirmation:
            Text("确认或修改转写文字后再提交。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $controller.transcriptText)
                .frame(minHeight: 160)
                .accessibilityLabel("转写文字")
                .accessibilityIdentifier(VoiceAnswerAccessibilityID.transcript)
            Button {
                submitConfirmedTranscript()
            } label: {
                Label("使用此文字", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(VoiceAnswerAccessibilityID.confirm)
        case .unavailable:
            Button("语音回答") {}
                .disabled(true)
                .accessibilityValue("当前设备无法本地转写")
                .accessibilityIdentifier(VoiceAnswerAccessibilityID.unavailable)
        case .failed:
            Button("重新检查") {
                Task {
                    await controller.cancel()
                    await controller.refreshCapability()
                }
            }
        case .cancelled:
            EmptyView()
        }
    }

    private func submitConfirmedTranscript() {
        do {
            let attempt = try submissionService.submitVoice(
                questionID: questionID,
                confirmedText: controller.transcriptText,
                audioAsset: try controller.audioAssetDraft(),
                context: modelContext
            )
            onSubmitted(attempt)
            dismiss()
        } catch {
            submissionError = error.localizedDescription
        }
    }
}
