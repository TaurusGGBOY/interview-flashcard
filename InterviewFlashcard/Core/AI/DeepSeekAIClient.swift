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

struct DeepSeekAIClient: AIClient {
    struct Configuration: Equatable, Sendable {
        let endpoint: URL
        let model: String
        let timeout: TimeInterval

        init(
            endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
            model: String,
            timeout: TimeInterval = 60
        ) {
            self.endpoint = endpoint
            self.model = model
            self.timeout = timeout
        }
    }

    private let configuration: Configuration
    private let apiKeyStore: any APIKeyStore
    private let transport: any AIHTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: Configuration,
        apiKeyStore: any APIKeyStore,
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) {
        self.configuration = configuration
        self.apiKeyStore = apiKeyStore
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        let response: DecomposeResponse = try await perform(.decompose, payload: request)
        try AIResponseValidator.validate(response, for: request)
        return response
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        let response: RefineResponse = try await perform(.refine, payload: request)
        // Topic mapping is deliberately a service-boundary policy: an unknown
        // model value becomes Others instead of discarding an otherwise valid batch.
        try AIResponseValidator.validate(response)
        return response
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        let response: ReclassifyResponse = try await perform(.reclassify, payload: request)
        try AIResponseValidator.validate(response, for: request)
        return response
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        let response: PolishResponse = try await perform(.polish, payload: request)
        try AIResponseValidator.validate(response, rawText: request.rawText)
        return response
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        let response: EvaluationResponse = try await perform(.evaluate, payload: request)
        // Validate the model's own metadata before canonicalizing it. A model
        // that answers with another prompt/rubric must not be silently accepted.
        try AIResponseValidator.validate(
            response,
            rubric: request.rubric,
            rawText: request.rawText,
            polishedText: request.polishedText,
            expectedPromptVersion: PromptCatalog.evaluateVersion
        )
        // Metadata is part of the client contract, not a model judgment. A
        // provider can occasionally echo a training-example model name (for
        // example `gpt-4o`), so persist the configured endpoint model and the
        // exact prompt version used by this client.
        let canonicalResponse = EvaluationResponse(
            scorable: response.scorable,
            notScorableReason: response.notScorableReason,
            dimensions: response.dimensions,
            factualErrors: response.factualErrors,
            strengths: response.strengths,
            gapsAndErrors: response.gapsAndErrors,
            improvements: response.improvements,
            polishOnlyClaims: response.polishOnlyClaims,
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: configuration.model,
            promptVersion: PromptCatalog.evaluateVersion,
            rubricVersion: request.rubric.version,
            completionStatus: response.completionStatus
        )
        try AIResponseValidator.validate(
            canonicalResponse,
            rubric: request.rubric,
            rawText: request.rawText,
            polishedText: request.polishedText,
            expectedPromptVersion: PromptCatalog.evaluateVersion
        )
        return canonicalResponse
    }

    private func perform<Request: Encodable, Response: Decodable>(
        _ operation: AIOperation,
        payload: Request
    ) async throws -> Response {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidResponse("A model setting is required")
        }
        guard let apiKey = try apiKeyStore.load(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.missingAPIKey
        }

        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            throw AIError.invalidResponse("Could not encode request payload")
        }
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw AIError.invalidResponse("Request payload was not UTF-8")
        }

        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: PromptCatalog.systemPrompt(for: operation)),
                .init(role: "user", content: payloadJSON)
            ],
            responseFormat: .init(type: "json_object"),
            temperature: 0
        )
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            urlRequest.httpBody = try encoder.encode(body)
        } catch {
            throw AIError.invalidResponse("Could not encode chat request")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch let error as AIError {
            throw error
        } catch let error as URLError {
            throw AIError.transport(String(describing: error.code))
        } catch {
            throw AIError.transport(String(describing: type(of: error)))
        }
        try validateHTTPStatus(response.statusCode)

        let envelope: ChatCompletionResponse
        do {
            envelope = try decoder.decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse("Could not decode chat response envelope")
        }
        guard let choice = envelope.choices.first else {
            throw AIError.invalidResponse("Chat response had no choice")
        }
        guard choice.finishReason == "stop" else {
            if choice.finishReason == "length" {
                throw AIError.truncatedResponse
            }
            throw AIError.invalidResponse("Unexpected finish reason")
        }
        guard let contentData = choice.message.content.data(using: .utf8) else {
            throw AIError.invalidResponse("Chat content was not UTF-8")
        }
        do {
            return try decoder.decode(Response.self, from: contentData)
        } catch {
            throw AIError.invalidResponse("Could not decode structured response")
        }
    }

    private func validateHTTPStatus(_ status: Int) throws {
        switch status {
        case 200..<300:
            return
        case 401, 403:
            throw AIError.unauthorized
        case 429:
            throw AIError.rateLimited
        case 408, 425, 500...599:
            throw AIError.transientHTTPStatus(status)
        default:
            throw AIError.httpStatus(status)
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let responseFormat: ResponseFormat
    let temperature: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
        let finishReason: String

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
}
