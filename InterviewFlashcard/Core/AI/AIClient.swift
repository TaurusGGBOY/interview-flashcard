import Foundation

protocol AIClient: Sendable {
    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse
    func refine(_ request: RefineRequest) async throws -> RefineResponse
    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse
    func polish(_ request: PolishRequest) async throws -> PolishResponse
    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse
}

enum AIError: Error, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case transientHTTPStatus(Int)
    case httpStatus(Int)
    case transport(String)
    case invalidResponse(String)
    case truncatedResponse
    case processingPaused

    var isTransient: Bool {
        switch self {
        case .rateLimited, .transientHTTPStatus, .transport:
            return true
        case .missingAPIKey, .unauthorized, .httpStatus, .invalidResponse,
             .truncatedResponse, .processingPaused:
            return false
        }
    }
}
