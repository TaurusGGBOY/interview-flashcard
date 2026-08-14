import Foundation
import SwiftData

@MainActor
struct AnswerSubmissionService {
    typealias ScheduleProcessing = @Sendable (UUID) -> Void

    enum SubmissionError: LocalizedError, Equatable {
        case questionNotFound
        case missingReferenceAnswer
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case .questionNotFound:
                "题目已不存在，请返回题库重新选择。"
            case .missingReferenceAnswer:
                "这道题还没有满分答案，暂时不能提交。"
            case .emptyAnswer:
                "回答不能为空。"
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
        let referenceAnswer = question.referenceAnswers.max(by: {
            if $0.version == $1.version {
                return $0.createdAt < $1.createdAt
            }
            return $0.version < $1.version
        })

        let submittedAt = now()
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: question.questionText,
            // The full-score answer is deliberately generated after the score
            // and feedback stages. Existing answers are still snapshotted
            // immediately; a missing answer is filled by stage three.
            referenceAnswerTextSnapshot: referenceAnswer?.answerText ?? "",
            referenceAnswerVersion: referenceAnswer?.version ?? 0,
            rawText: normalizedText,
            inputMode: .typed,
            processingStatus: .saved,
            startedAt: submittedAt,
            submittedAt: submittedAt,
            question: question
        )
        context.insert(attempt)
        try context.save()
        diagnosticExporter?.exportIgnoringErrors(from: context)
        scheduleProcessing(attempt.id)
        return attempt
    }
}

private extension DiagnosticStateExporter {
    func exportIgnoringErrors(from context: ModelContext) {
        try? export(from: context)
    }
}
