import Foundation

protocol AIHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionAIHTTPTransport: AIHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Response was not HTTP")
        }
        return (data, httpResponse)
    }
}

/// Compatibility wrapper for existing call sites and tests. New production
/// requests use the dynamic provider router.
struct DeepSeekAIClient: AIClient {
    struct Configuration: Equatable, Sendable {
        let endpoint: URL
        let model: String
        let timeout: TimeInterval

        init(
            endpoint: URL = URL(string: "https://opencode.ai/zen/go/v1/responses")!,
            model: String,
            timeout: TimeInterval = 600
        ) {
            self.endpoint = endpoint
            self.model = model
            self.timeout = timeout
        }
    }

    private let configuration: Configuration
    private let apiKeyStore: any APIKeyStore
    private let transport: any AIHTTPTransport

    init(
        configuration: Configuration,
        apiKeyStore: any APIKeyStore,
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) {
        self.configuration = configuration
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
        guard let apiKey = try apiKeyStore.load(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIError.missingAPIKey
        }
        return ConfiguredAIClient(
            configuration: AIProviderConfiguration(
                provider: .openAI,
                baseURL: configuration.endpoint.absoluteString,
                model: configuration.model
            ),
            apiKey: apiKey,
            transport: transport,
            timeout: configuration.timeout
        )
    }
}
