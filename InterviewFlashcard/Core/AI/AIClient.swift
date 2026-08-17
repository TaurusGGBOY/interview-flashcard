import Foundation

protocol AIClient: Sendable {
    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse
    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse
    func refine(_ request: RefineRequest) async throws -> RefineResponse
    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse
    func polish(_ request: PolishRequest) async throws -> PolishResponse
    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse
    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse
    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse
}

extension AIClient {
    /// Older deterministic test clients do not need the lazy answer path.
    /// Production clients override this with the provider-backed request.
    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        throw AIError.invalidResponse("Reference answer generation is not configured")
    }

    /// Compatibility fallback for deterministic clients that still implement
    /// the original one-shot evaluator. Production clients override both
    /// staged calls with their smaller provider requests.
    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        let response = try await evaluate(request.asEvaluationRequest())
        return EvaluationScoreResponse(
            scorable: response.scorable,
            notScorableReason: response.notScorableReason,
            dimensions: response.dimensions.map { .init(key: $0.key, score: $0.score) },
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: response.modelID,
            promptVersion: PromptCatalog.evaluateScoreVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        let response = try await evaluate(request.asEvaluationRequest())
        return EvaluationFeedbackResponse(
            dimensions: response.dimensions.map {
                .init(
                    key: $0.key,
                    evidence: $0.evidence,
                    missedPoints: $0.missedPoints,
                    feedback: $0.feedback
                )
            },
            factualErrors: response.factualErrors,
            strengths: response.strengths,
            gapsAndErrors: response.gapsAndErrors,
            improvements: response.improvements,
            polishOnlyClaims: response.polishOnlyClaims,
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: response.modelID,
            promptVersion: PromptCatalog.evaluateFeedbackVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
    }
}

enum AIError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case transientHTTPStatus(Int)
    case httpStatus(Int)
    case transport(String)
    case invalidResponse(String)
    case malformedStructuredResponse
    case truncatedResponse
    case processingPaused

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "未配置 AI API Key。"
        case .unauthorized:
            "AI 服务鉴权失败，请检查 API Key。"
        case .rateLimited:
            "AI 服务限流，稍后重试。"
        case let .transientHTTPStatus(status):
            "AI 服务暂时不可用（HTTP \(status)），请重试评分。"
        case let .httpStatus(status):
            "AI 服务请求失败（HTTP \(status)）。"
        case let .transport(detail):
            "AI 服务网络连接失败（\(detail)）。"
        case let .invalidResponse(detail):
            "AI 返回内容无法解析：\(detail)"
        case .malformedStructuredResponse:
            "AI 返回内容不是有效的结构化评分结果。"
        case .truncatedResponse:
            "AI 返回内容不完整，请重试评分。"
        case .processingPaused:
            "评分处理已暂停。"
        }
    }

    var isTransient: Bool {
        switch self {
        case .rateLimited, .transientHTTPStatus, .transport:
            return true
        case .missingAPIKey, .unauthorized, .httpStatus, .invalidResponse,
             .truncatedResponse, .processingPaused:
            return false
        case .malformedStructuredResponse:
            return true
        }
    }
}
