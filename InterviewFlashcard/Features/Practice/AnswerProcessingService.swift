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

    /// Stage 1: request only the six numeric judgments. The partial
    /// EvaluationRecord is persisted before this method returns, so the UI can
    /// render the total and dimension scores without waiting for prose.
    @discardableResult
    func score(
        attemptID: UUID,
        context: ModelContext,
        forceRescore: Bool = false
    ) async throws -> EvaluationRecord {
        let attempt = try fetchAttempt(attemptID, context: context)
        if !forceRescore,
           let existing = latestEvaluation(for: attempt),
           existing.status == .feedback || existing.status == .completed {
            return existing
        }

        do {
            attempt.processingStatus = .scoring
            attempt.failureSummary = nil
            try context.save()
            try? diagnosticExporter?.export(from: context)

            let response = try await aiClient.score(
                EvaluationScoreRequest(
                    requestID: attemptID,
                    question: attempt.questionTextSnapshot,
                    referenceAnswer: attempt.referenceAnswerTextSnapshot,
                    sourceBackedMaterial: sourceBackedMaterial(for: attempt.question),
                    rawText: attempt.rawText,
                    rubric: .seniorSoftwareEngineer
                )
            )
            try AIResponseValidator.validate(response, rubric: .seniorSoftwareEngineer)

            let scores = dimensionScores(from: response.dimensions)
            let total = response.scorable
                ? ScoringRubric.general.total(for: scores)
                : nil
            let evaluation = EvaluationRecord(
                totalScore: total,
                scores: scores,
                strengthsJSON: "[]",
                nextAnswerPlanJSON: "[]",
                factualErrorsJSON: "[]",
                feedbackJSON: "{}",
                confidence: String(format: "%.2f", response.confidence),
                status: response.scorable ? .feedback : .completed,
                provider: "deepseek-compatible",
                modelID: response.modelID,
                promptVersion: response.promptVersion,
                rubricVersion: response.rubricVersion,
                createdAt: now(),
                attempt: attempt,
                polishResultID: nil
            )
            context.insert(evaluation)
            attempt.processingStatus = response.scorable ? .feedback : .completed
            attempt.failureSummary = response.scorable ? nil : response.notScorableReason
            try context.save()
            try? diagnosticExporter?.export(from: context)
            return evaluation
        } catch {
            attempt.processingStatus = .failed
            attempt.failureSummary = String(describing: error)
            try? context.save()
            try? diagnosticExporter?.export(from: context)
            throw error
        }
    }

    /// Re-run the complete staged evaluation for an existing answer. This is
    /// intentionally available for successful answers as well as failed ones:
    /// a user may want a fresh score after changing the rubric or provider.
    @discardableResult
    func rescore(attemptID: UUID, context: ModelContext) async throws -> EvaluationRecord {
        let evaluation = try await score(
            attemptID: attemptID,
            context: context,
            forceRescore: true
        )
        guard evaluation.status == .feedback else { return evaluation }
        try await completeFeedback(
            attemptID: attemptID,
            evaluationID: evaluation.id,
            context: context
        )
        _ = try await prepareReferenceAnswer(attemptID: attemptID, context: context)
        return evaluation
    }

    /// Stage 2: fill in evidence and per-dimension feedback using the already
    /// persisted scores. Scores are never allowed to change in this stage.
    func completeFeedback(
        attemptID: UUID,
        evaluationID: UUID,
        context: ModelContext
    ) async throws {
        let attempt = try fetchAttempt(attemptID, context: context)
        let evaluation = try fetchEvaluation(evaluationID, context: context)
        guard evaluation.attempt.id == attempt.id else {
            throw ProcessingError.attemptNotFound
        }

        do {
            attempt.processingStatus = .feedback
            try context.save()
            let scores = ScoreDimension.allCases.map {
                EvaluationScoreDimension(key: $0, score: evaluation.dimensionScores[$0])
            }
            var usedFallback = false
            let response: EvaluationFeedbackResponse
            do {
                response = try await aiClient.evaluationFeedback(
                    EvaluationFeedbackRequest(
                        requestID: evaluationID,
                        question: attempt.questionTextSnapshot,
                        referenceAnswer: attempt.referenceAnswerTextSnapshot,
                        sourceBackedMaterial: sourceBackedMaterial(for: attempt.question),
                        rawText: attempt.rawText,
                        scores: scores,
                        rubric: .seniorSoftwareEngineer
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A provider can return a valid score and then fail the
                // feedback stage with malformed JSON, an incompatible schema,
                // or a transport error. Do not turn the already-persisted
                // score into a failed attempt. Keep strict validation for
                // provider feedback, but finish this stage with auditable,
                // evidence-safe placeholders so reference-answer generation
                // and later retry/recovery remain available.
                usedFallback = true
                response = Self.fallbackFeedback(
                    scores: scores,
                    evaluation: evaluation,
                    rawText: attempt.rawText,
                    error: error
                )
            }
            try AIResponseValidator.validate(
                response,
                scores: scores,
                rubric: .seniorSoftwareEngineer,
                rawText: attempt.rawText
            )
            let canonical = response.asEvaluationResponse(scores: scores)
            evaluation.strengthsJSON = try encoded(response.strengths)
            evaluation.nextAnswerPlanJSON = try encoded(response.improvements)
            evaluation.factualErrorsJSON = try encoded(response.factualErrors)
            evaluation.feedbackJSON = try encoded(EvaluationDetailPayload(evaluation: canonical))
            evaluation.confidence = String(format: "%.2f", response.confidence)
            evaluation.provider = usedFallback ? "local-safe-fallback" : "deepseek-compatible"
            evaluation.modelID = response.modelID
            evaluation.promptVersion = response.promptVersion
            evaluation.rubricVersion = response.rubricVersion
            evaluation.status = .completed
            attempt.processingStatus = .referenceAnswer
            attempt.failureSummary = nil
            try context.save()
            try? diagnosticExporter?.export(from: context)
        } catch {
            evaluation.status = .failed
            attempt.processingStatus = .failed
            attempt.failureSummary = String(describing: error)
            try? context.save()
            try? diagnosticExporter?.export(from: context)
            throw error
        }
    }

    /// Stage 3: generate and snapshot the full-score answer only after the
    /// numeric score and detailed feedback have already been shown.
    @discardableResult
    func prepareReferenceAnswer(attemptID: UUID, context: ModelContext) async throws -> ReferenceAnswerVersionRecord {
        let attempt = try fetchAttempt(attemptID, context: context)
        do {
            attempt.processingStatus = .referenceAnswer
            try context.save()
            let answer = try await ReferenceAnswerService(
                aiClient: aiClient,
                now: now,
                diagnosticExporter: diagnosticExporter
            ).ensureReferenceAnswer(
                questionID: attempt.question.id,
                context: context
            )
            attempt.referenceAnswerTextSnapshot = answer.answerText
            attempt.referenceAnswerVersion = answer.version
            attempt.processingStatus = .completed
            attempt.failureSummary = nil
            try context.save()
            try? diagnosticExporter?.export(from: context)
            return answer
        } catch {
            attempt.processingStatus = .failed
            attempt.failureSummary = String(describing: error)
            try? context.save()
            try? diagnosticExporter?.export(from: context)
            throw error
        }
    }

    /// Runs the three stages in order for recovery and non-UI callers. The UI
    /// calls the individual methods so it can publish the score immediately.
    @discardableResult
    func processStaged(attemptID: UUID, context: ModelContext) async throws -> EvaluationRecord {
        let evaluation = try await score(attemptID: attemptID, context: context)
        guard evaluation.status == .feedback else { return evaluation }
        try await completeFeedback(
            attemptID: attemptID,
            evaluationID: evaluation.id,
            context: context
        )
        _ = try await prepareReferenceAnswer(attemptID: attemptID, context: context)
        return evaluation
    }

    /// Resumes whichever staged boundary was persisted before an app
    /// interruption. This keeps a visible score intact and never starts a
    /// second score request when only feedback or the reference answer is
    /// still pending.
    @discardableResult
    func resume(attemptID: UUID, context: ModelContext) async throws -> EvaluationRecord {
        let attempt = try fetchAttempt(attemptID, context: context)
        if attempt.processingStatus == .referenceAnswer,
           let evaluation = latestEvaluation(for: attempt),
           evaluation.status == .completed {
            _ = try await prepareReferenceAnswer(attemptID: attemptID, context: context)
            return evaluation
        }
        return try await processStaged(attemptID: attemptID, context: context)
    }

    /// Runs one direct evaluation request. The evaluator is told that text may be
    /// an on-device speech transcript, so the answer history keeps the user's
    /// submitted text and never creates a separate AI-polished revision.
    @discardableResult
    func process(attemptID: UUID, context: ModelContext) async throws -> EvaluationRecord {
        let attempt = try fetchAttempt(attemptID, context: context)

        do {
            attempt.processingStatus = .evaluating
            attempt.failureSummary = nil
            try context.save()
            try? diagnosticExporter?.export(from: context)

            let evaluation = try await aiClient.evaluate(
                EvaluationRequest(
                    question: attempt.questionTextSnapshot,
                    referenceAnswer: attempt.referenceAnswerTextSnapshot,
                    rawText: attempt.rawText,
                    // Keep the legacy request fields populated for wire/schema
                    // compatibility. The v2 evaluation prompt treats rawText as
                    // the sole source of answer evidence.
                    polishedText: attempt.rawText,
                    introducedClaims: [],
                    rubric: .seniorSoftwareEngineer
                )
            )
            try AIResponseValidator.validate(
                evaluation,
                rubric: EvaluationRubric.seniorSoftwareEngineer,
                rawText: attempt.rawText,
                polishedText: attempt.rawText
            )

            let scores = DimensionScores(
                correctness: evaluation.score(for: .correctness),
                coverage: evaluation.score(for: .coverage),
                reasoning: evaluation.score(for: .reasoning),
                structure: evaluation.score(for: .structure),
                tradeoffs: evaluation.score(for: .tradeoffs),
                precision: evaluation.score(for: .precision)
            )
            let total = evaluation.scorable
                ? EvaluationRubric.seniorSoftwareEngineer.total(for: evaluation.dimensions)
                : nil
            let detailPayload = EvaluationDetailPayload(evaluation: evaluation)
            let evaluationRecord = EvaluationRecord(
                totalScore: total,
                scores: scores,
                strengthsJSON: try encoded(evaluation.strengths),
                nextAnswerPlanJSON: try encoded(evaluation.improvements),
                factualErrorsJSON: try encoded(evaluation.factualErrors),
                feedbackJSON: try encoded(detailPayload),
                confidence: String(format: "%.2f", evaluation.confidence),
                status: .completed,
                provider: "deepseek-compatible",
                modelID: evaluation.modelID,
                promptVersion: evaluation.promptVersion,
                rubricVersion: evaluation.rubricVersion,
                createdAt: now(),
                attempt: attempt,
                polishResultID: nil
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

    private func fetchAttempt(_ id: UUID, context: ModelContext) throws -> AnswerAttemptRecord {
        let descriptor = FetchDescriptor<AnswerAttemptRecord>(
            predicate: #Predicate { attempt in attempt.id == id }
        )
        guard let attempt = try context.fetch(descriptor).first else {
            throw ProcessingError.attemptNotFound
        }
        return attempt
    }

    private func fetchEvaluation(_ id: UUID, context: ModelContext) throws -> EvaluationRecord {
        let descriptor = FetchDescriptor<EvaluationRecord>(
            predicate: #Predicate { evaluation in evaluation.id == id }
        )
        guard let evaluation = try context.fetch(descriptor).first else {
            throw ProcessingError.attemptNotFound
        }
        return evaluation
    }

    private func latestEvaluation(for attempt: AnswerAttemptRecord) -> EvaluationRecord? {
        attempt.evaluations.max { $0.createdAt < $1.createdAt }
    }

    private func dimensionScores(from dimensions: [EvaluationScoreDimension]) -> DimensionScores {
        let values = Dictionary(uniqueKeysWithValues: dimensions.map { ($0.key, $0.score) })
        return DimensionScores(
            correctness: values[.correctness] ?? 0,
            coverage: values[.coverage] ?? 0,
            reasoning: values[.reasoning] ?? 0,
            structure: values[.structure] ?? 0,
            tradeoffs: values[.tradeoffs] ?? 0,
            precision: values[.precision] ?? 0
        )
    }

    private static func fallbackFeedback(
        scores: [EvaluationScoreDimension],
        evaluation: EvaluationRecord,
        rawText: String,
        error: any Error
    ) -> EvaluationFeedbackResponse {
        let scoreMap = Dictionary(uniqueKeysWithValues: scores.map { ($0.key, $0.score) })
        let total = evaluation.totalScore ?? ScoringRubric.general.total(
            for: DimensionScores(
                correctness: scoreMap[.correctness] ?? 0,
                coverage: scoreMap[.coverage] ?? 0,
                reasoning: scoreMap[.reasoning] ?? 0,
                structure: scoreMap[.structure] ?? 0,
                tradeoffs: scoreMap[.tradeoffs] ?? 0,
                precision: scoreMap[.precision] ?? 0
            )
        )
        let quote = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dimensions = ScoreDimension.allCases.map { dimension in
            let score = scoreMap[dimension] ?? 0
            return EvaluationFeedbackDimension(
                key: dimension,
                evidence: [
                    EvaluationEvidence(
                        quote: quote,
                        explanation: "评分依据保留为用户提交的原始回答。"
                    )
                ],
                missedPoints: score < 100
                    ? ["请补充\(dimension.displayName)相关的机制、边界条件和工程取舍。"]
                    : [],
                feedback: "详细评语服务返回字段不完整；本维度分数已保留。"
            )
        }
        let confidence = Double(evaluation.confidence) ?? 0
        return EvaluationFeedbackResponse(
            dimensions: dimensions,
            factualErrors: [],
            strengths: [],
            gapsAndErrors: ["详细评语服务返回字段不完整，以上分数仍然有效。"],
            improvements: ["根据六维分数补充机制、边界条件和工程取舍。"],
            polishOnlyClaims: [],
            confidence: min(max(confidence, 0), 1),
            scoreRange: ScoreRange(low: total, high: total),
            warnings: [
                "评语服务未返回完整结构（\(String(describing: error))），已使用安全降级内容。"
            ],
            modelID: evaluation.modelID,
            promptVersion: PromptCatalog.evaluateFeedbackVersion,
            rubricVersion: EvaluationRubric.seniorSoftwareEngineer.version,
            completionStatus: .complete
        )
    }

    private func sourceBackedMaterial(for question: QuestionCardRecord) -> String {
        let candidates = question.sourceDocument.importRuns
            .flatMap(\.chunks)
            .flatMap(\.candidates)
        return candidates
            .first {
                $0.sourceAnchor == question.sourceAnchor ||
                    $0.questionText == question.questionText
            }?
            .proposedAnswerText ?? ""
    }
}

/// Prepares and persists the reference answer when a user first opens a
/// question. Import deliberately stores only extraction material; this service
/// is the lazy boundary that turns that material into a reusable answer.
@MainActor
struct ReferenceAnswerService {
    enum PreparationError: LocalizedError, Equatable {
        case questionNotFound

        var errorDescription: String? {
            switch self {
            case .questionNotFound:
                "题目已不存在，无法准备满分答案。"
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

    @discardableResult
    func ensureReferenceAnswer(
        questionID: UUID,
        context: ModelContext
    ) async throws -> ReferenceAnswerVersionRecord {
        let descriptor = FetchDescriptor<QuestionCardRecord>(
            predicate: #Predicate { question in
                question.id == questionID && question.trashedAt == nil
            }
        )
        guard let question = try context.fetch(descriptor).first else {
            throw PreparationError.questionNotFound
        }

        if let existing = latestReferenceAnswer(for: question) {
            return existing
        }

        let response = try await aiClient.referenceAnswer(
            ReferenceAnswerRequest(
                sourceDocumentID: question.sourceDocument.id,
                question: question.questionText,
                sourceBackedMaterial: sourceBackedMaterial(for: question)
            )
        )
        try AIResponseValidator.validate(response)

        // Re-read after the network request so a previously completed request
        // wins over this one if the user opened the same question twice.
        if let existing = latestReferenceAnswer(for: question) {
            return existing
        }

        let nextVersion = (question.referenceAnswers.map(\.version).max() ?? 0) + 1
        let answer = ReferenceAnswerVersionRecord(
            version: nextVersion,
            answerText: response.answerText,
            keyPointsJSON: try encoded(response.keyPoints),
            origin: .aiGenerated,
            modelID: response.modelID,
            promptVersion: response.promptVersion,
            createdAt: now(),
            question: question
        )
        context.insert(answer)
        try context.save()
        try? diagnosticExporter?.export(from: context)
        return answer
    }

    private func latestReferenceAnswer(
        for question: QuestionCardRecord
    ) -> ReferenceAnswerVersionRecord? {
        question.referenceAnswers.max {
            if $0.version == $1.version {
                return $0.createdAt < $1.createdAt
            }
            return $0.version < $1.version
        }
    }

    private func sourceBackedMaterial(for question: QuestionCardRecord) -> String {
        let candidates = question.sourceDocument.importRuns
            .flatMap(\.chunks)
            .flatMap(\.candidates)

        return candidates
            .first {
                $0.sourceAnchor == question.sourceAnchor ||
                    $0.questionText == question.questionText
            }?
            .proposedAnswerText ?? ""
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
