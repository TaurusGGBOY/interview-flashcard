import Foundation
import SwiftData

@MainActor
struct AnswerProcessingService {
    enum ProcessingError: LocalizedError, Equatable {
        case attemptNotFound
        case answerNotScorable

        var errorDescription: String? {
            switch self {
            case .attemptNotFound:
                "回答记录不存在，可能已被删除。"
            case .answerNotScorable:
                "这次回答没有足够内容可评分。"
            }
        }
    }

    let aiClient: any AIClient
    let now: @Sendable () -> Date
    let diagnosticExporter: DiagnosticStateExporter?

    init(
        aiClient: any AIClient,
        now: @escaping @Sendable () -> Date = Date.init,
        diagnosticExporter: DiagnosticStateExporter? = nil
    ) {
        self.aiClient = aiClient
        self.now = now
        self.diagnosticExporter = diagnosticExporter
    }

    /// Runs polish first and then evaluation. Each run appends a new polish/evaluation
    /// revision, so retry never overwrites the answer history.
    @discardableResult
    func process(attemptID: UUID, context: ModelContext) async throws -> EvaluationRecord {
        let descriptor = FetchDescriptor<AnswerAttemptRecord>(
            predicate: #Predicate { attempt in attempt.id == attemptID }
        )
        guard let attempt = try context.fetch(descriptor).first else {
            throw ProcessingError.attemptNotFound
        }

        do {
            attempt.processingStatus = .polishing
            attempt.failureSummary = nil
            try context.save()
            try? diagnosticExporter?.export(from: context)

            let polish = try await aiClient.polish(
                PolishRequest(
                    rawText: attempt.rawText,
                    localeIdentifier: Locale.current.identifier,
                    terminologyHints: []
                )
            )
            try AIResponseValidator.validate(polish, rawText: attempt.rawText)

            let polishRevision = (attempt.polishResults.map(\.revision).max() ?? 0) + 1
            let polishRecord = PolishResultRecord(
                revision: polishRevision,
                inputText: attempt.rawText,
                polishedText: polish.polishedText,
                editSummaryJSON: try encoded(polish.edits),
                suspectedASRErrorsJSON: try encoded(polish.suspectedTranscriptionIssues),
                introducedClaimsJSON: try encoded(polish.introducedClaims),
                needsUserReview: polish.needsUserReview,
                promptVersion: polish.promptVersion,
                modelID: polish.modelID,
                createdAt: now(),
                attempt: attempt
            )
            context.insert(polishRecord)

            attempt.processingStatus = .evaluating
            try context.save()
            try? diagnosticExporter?.export(from: context)

            let evaluation = try await aiClient.evaluate(
                EvaluationRequest(
                    question: attempt.questionTextSnapshot,
                    referenceAnswer: attempt.referenceAnswerTextSnapshot,
                    rawText: attempt.rawText,
                    polishedText: polish.polishedText,
                    introducedClaims: polish.introducedClaims,
                    rubric: .general
                )
            )
            try AIResponseValidator.validate(
                evaluation,
                rubric: EvaluationRubric.general,
                rawText: attempt.rawText,
                polishedText: polish.polishedText
            )

            let scores = DimensionScores(
                correctness: evaluation.score(for: .correctness),
                coverage: evaluation.score(for: .coverage),
                reasoning: evaluation.score(for: .reasoning),
                structure: evaluation.score(for: .structure),
                tradeoffs: evaluation.score(for: .tradeoffs),
                precision: evaluation.score(for: .precision)
            )
            let total = evaluation.scorable ? EvaluationRubric.general.total(for: evaluation.dimensions) : nil
            let evaluationRecord = EvaluationRecord(
                totalScore: total,
                scores: scores,
                strengthsJSON: try encoded(evaluation.strengths),
                nextAnswerPlanJSON: try encoded(evaluation.improvements),
                factualErrorsJSON: try encoded(evaluation.factualErrors),
                feedbackJSON: try encoded(
                    evaluation.dimensions.reduce(into: [String: String]()) { result, dimension in
                        result[dimension.key.rawValue] = dimension.feedback
                    }
                ),
                confidence: String(format: "%.2f", evaluation.confidence),
                status: .completed,
                provider: "deepseek-compatible",
                modelID: evaluation.modelID,
                promptVersion: evaluation.promptVersion,
                rubricVersion: evaluation.rubricVersion,
                createdAt: now(),
                attempt: attempt,
                polishResultID: polishRecord.id
            )
            context.insert(evaluationRecord)
            attempt.processingStatus = .completed
            attempt.failureSummary = evaluation.scorable ? nil : evaluation.notScorableReason
            try context.save()
            try? diagnosticExporter?.export(from: context)
            return evaluationRecord
        } catch {
            attempt.processingStatus = .failed
            attempt.failureSummary = String(describing: error)
            try? context.save()
            try? diagnosticExporter?.export(from: context)
            throw error
        }
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension EvaluationResponse {
    func score(for dimension: ScoreDimension) -> Int {
        dimensions.first(where: { $0.key == dimension })?.score ?? 0
    }
}
