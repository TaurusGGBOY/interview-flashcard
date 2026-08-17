import Foundation

struct DynamicAIClientRouter: AIClient {
    private let configurationStore: any AIConfigurationStore
    private let apiKeyStore: any APIKeyStore
    private let transport: any AIHTTPTransport

    init(
        configurationStore: any AIConfigurationStore,
        apiKeyStore: any APIKeyStore,
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) {
        self.configurationStore = configurationStore
        self.apiKeyStore = apiKeyStore
        self.transport = transport
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await resolvedClient().decompose(request)
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        try await resolvedClient().referenceAnswer(request)
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await resolvedClient().refine(request)
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await resolvedClient().reclassify(request)
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await resolvedClient().polish(request)
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await resolvedClient().evaluate(request)
    }

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        try await resolvedClient().score(request)
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        try await resolvedClient().evaluationFeedback(request)
    }

    private func resolvedClient() throws -> ConfiguredAIClient {
        let configuration = configurationStore.load()
        guard let apiKey = try apiKeyStore.load(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIError.missingAPIKey
        }
        return ConfiguredAIClient(
            configuration: configuration,
            apiKey: apiKey,
            transport: transport
        )
    }
}
