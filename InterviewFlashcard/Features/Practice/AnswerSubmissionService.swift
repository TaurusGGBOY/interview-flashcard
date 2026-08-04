import Foundation
import SwiftData

@MainActor
struct AnswerSubmissionService {
    typealias ScheduleProcessing = @Sendable (UUID) -> Void

    struct AudioAssetDraft: Sendable {
        let relativePath: String
        let format: String
        let duration: Double
        let byteCount: Int64
        let checksum: String
        let transcriptionEngine: String
        let localeIdentifier: String
        let confidenceSummary: String?

        init(
            relativePath: String,
            format: String = "m4a",
            duration: Double,
            byteCount: Int64,
            checksum: String,
            transcriptionEngine: String,
            localeIdentifier: String,
            confidenceSummary: String? = nil
        ) {
            self.relativePath = relativePath
            self.format = format
            self.duration = duration
            self.byteCount = byteCount
            self.checksum = checksum
            self.transcriptionEngine = transcriptionEngine
            self.localeIdentifier = localeIdentifier
            self.confidenceSummary = confidenceSummary
        }
    }

    enum SubmissionError: LocalizedError, Equatable {
        case questionNotFound
        case missingReferenceAnswer
        case emptyAnswer
        case missingAudioAsset

        var errorDescription: String? {
            switch self {
            case .questionNotFound:
                "题目已不存在，请返回题库重新选择。"
            case .missingReferenceAnswer:
                "这道题还没有满分答案，暂时不能提交。"
            case .emptyAnswer:
                "回答不能为空。"
            case .missingAudioAsset:
                "语音回答缺少本地录音，请重新录制。"
            }
        }
    }

    let now: @Sendable () -> Date
    let scheduleProcessing: ScheduleProcessing
    let diagnosticExporter: DiagnosticStateExporter?

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        scheduleProcessing: @escaping ScheduleProcessing = { _ in },
        diagnosticExporter: DiagnosticStateExporter? = nil
    ) {
        self.now = now
        self.scheduleProcessing = scheduleProcessing
        self.diagnosticExporter = diagnosticExporter
    }

    @discardableResult
    func submitText(
        questionID: UUID,
        rawText: String,
        context: ModelContext
    ) throws -> AnswerAttemptRecord {
        try submit(
            questionID: questionID,
            rawText: rawText,
            inputMode: .typed,
            context: context
        )
    }

    @discardableResult
    func submitVoice(
        questionID: UUID,
        confirmedText: String,
        audioAsset: AudioAssetDraft?,
        context: ModelContext
    ) throws -> AnswerAttemptRecord {
        guard !confirmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubmissionError.emptyAnswer
        }
        guard let audioAsset else {
            throw SubmissionError.missingAudioAsset
        }
        let attempt = try submit(
            questionID: questionID,
            rawText: confirmedText,
            inputMode: .voice,
            context: context,
            persistBeforeScheduling: false
        )
        context.insert(
            AudioAssetRecord(
                relativePath: audioAsset.relativePath,
                format: audioAsset.format,
                duration: audioAsset.duration,
                byteCount: audioAsset.byteCount,
                checksum: audioAsset.checksum,
                transcriptionEngine: audioAsset.transcriptionEngine,
                localeIdentifier: audioAsset.localeIdentifier,
                confidenceSummary: audioAsset.confidenceSummary,
                attempt: attempt
            )
        )
        try context.save()
        diagnosticExporter?.exportIgnoringErrors(from: context)
        scheduleProcessing(attempt.id)
        return attempt
    }

    private func submit(
        questionID: UUID,
        rawText: String,
        inputMode: AnswerInputMode,
        context: ModelContext,
        persistBeforeScheduling: Bool = true
    ) throws -> AnswerAttemptRecord {
        let normalizedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw SubmissionError.emptyAnswer
        }

        let descriptor = FetchDescriptor<QuestionCardRecord>(
            predicate: #Predicate { question in
                question.id == questionID && question.trashedAt == nil
            }
        )
        guard let question = try context.fetch(descriptor).first else {
            throw SubmissionError.questionNotFound
        }
        guard let referenceAnswer = question.referenceAnswers.max(by: {
            if $0.version == $1.version {
                return $0.createdAt < $1.createdAt
            }
            return $0.version < $1.version
        }) else {
            throw SubmissionError.missingReferenceAnswer
        }

        let submittedAt = now()
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: question.questionText,
            referenceAnswerTextSnapshot: referenceAnswer.answerText,
            referenceAnswerVersion: referenceAnswer.version,
            rawText: normalizedText,
            inputMode: inputMode,
            processingStatus: .saved,
            startedAt: submittedAt,
            submittedAt: submittedAt,
            question: question
        )
        context.insert(attempt)
        try context.save()
        diagnosticExporter?.exportIgnoringErrors(from: context)
        if persistBeforeScheduling {
            scheduleProcessing(attempt.id)
        }
        return attempt
    }
}

private extension DiagnosticStateExporter {
    func exportIgnoringErrors(from context: ModelContext) {
        try? export(from: context)
    }
}
