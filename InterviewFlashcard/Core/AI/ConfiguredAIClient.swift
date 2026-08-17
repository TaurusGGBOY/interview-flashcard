import Foundation

struct ConfiguredAIClient: AIClient {
    private let configuration: AIProviderConfiguration
    private let apiKey: String
    private let transport: any AIHTTPTransport
    private let timeout: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: AIProviderConfiguration,
        apiKey: String,
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport(),
        // DeepSeek's structured responses can spend several minutes in
        // generation before the complete JSON object is available. The
        // importer runs asynchronously, so prefer waiting for a valid
        // response over aborting at the old 60-second limit.
        timeout: TimeInterval = 600
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.transport = transport
        self.timeout = timeout
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        let response: DecomposeResponse = try await perform(
            .decompose,
            payload: request,
            systemPrompt: PromptCatalog.systemPrompt(
                for: .decompose,
                decomposeOutputMode: request.outputMode,
                availableTopicNames: request.availableTopicNames
            )
        )
        // The import coordinator canonicalizes model-provided anchors against
        // the persisted Markdown before applying strict source validation.
        // Do not validate provider offsets here: they may be byte/character
        // offsets or otherwise incomplete even when exactQuote is correct.
        return response
    }

    func referenceAnswer(_ request: ReferenceAnswerRequest) async throws -> ReferenceAnswerResponse {
        let response: ReferenceAnswerResponse = try await perform(
            .referenceAnswer,
            payload: request
        )
        let canonicalResponse = ReferenceAnswerResponse(
            answerText: response.answerText,
            keyPoints: response.keyPoints,
            modelID: configuration.model,
            promptVersion: response.promptVersion,
            completionStatus: response.completionStatus
        )
        try AIResponseValidator.validate(canonicalResponse)
        return canonicalResponse
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        let response: RefineResponse = try await perform(
            .refine,
            payload: request,
            systemPrompt: PromptCatalog.systemPrompt(
                for: .refine,
                availableTopicNames: request.availableTopicNames
            )
        )
        try AIResponseValidator.validate(response, allowedTopics: Set(request.availableTopicNames))
        return response
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        let response: ReclassifyResponse = try await perform(
            .reclassify,
            payload: request,
            systemPrompt: PromptCatalog.systemPrompt(
                for: .reclassify,
                availableTopicNames: request.availableTopicNames
            )
        )
        try AIResponseValidator.validate(response, for: request, enforceTopicWhitelist: true)
        return response
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        let response: PolishResponse = try await perform(.polish, payload: request)
        try AIResponseValidator.validate(response, rawText: request.rawText)
        return response
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        let response: EvaluationResponse = try await perform(.evaluate, payload: request)
        try AIResponseValidator.validate(
            response,
            rubric: request.rubric,
            rawText: request.rawText,
            polishedText: request.polishedText,
            expectedPromptVersion: PromptCatalog.evaluateVersion
        )
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

    func score(_ request: EvaluationScoreRequest) async throws -> EvaluationScoreResponse {
        let response: EvaluationScoreResponse = try await perform(
            .evaluateScore,
            payload: request
        )
        let canonicalResponse = EvaluationScoreResponse(
            scorable: response.scorable,
            notScorableReason: response.notScorableReason,
            dimensions: response.dimensions,
            confidence: response.confidence,
            scoreRange: response.scoreRange,
            warnings: response.warnings,
            modelID: configuration.model,
            promptVersion: response.promptVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
        try AIResponseValidator.validate(canonicalResponse, rubric: request.rubric)
        return canonicalResponse
    }

    func evaluationFeedback(_ request: EvaluationFeedbackRequest) async throws -> EvaluationFeedbackResponse {
        let response: EvaluationFeedbackResponse = try await perform(
            .evaluateFeedback,
            payload: request
        )
        let canonicalResponse = EvaluationFeedbackResponse(
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
            promptVersion: response.promptVersion,
            rubricVersion: response.rubricVersion,
            completionStatus: response.completionStatus
        )
        try AIResponseValidator.validate(
            canonicalResponse,
            scores: request.scores,
            rubric: request.rubric,
            rawText: request.rawText
        )
        return canonicalResponse
    }

    private func perform<Request: Encodable, Response: Decodable>(
        _ operation: AIOperation,
        payload: Request,
        systemPrompt: String? = nil
    ) async throws -> Response {
        let payloadData: Data
        do {
            payloadData = try encoder.encode(payload)
        } catch {
            throw AIError.invalidResponse("Could not encode request payload")
        }
        guard let payloadJSON = String(data: payloadData, encoding: .utf8) else {
            throw AIError.invalidResponse("Request payload was not UTF-8")
        }

        let adapter = AIProviderAdapterFactory.make(for: configuration.provider)
        let request = try adapter.makeRequest(
            configuration: configuration,
            apiKey: apiKey,
            systemPrompt: systemPrompt ?? PromptCatalog.systemPrompt(for: operation),
            userMessage: payloadJSON,
            mode: .structuredJSON,
            timeout: timeout,
            maxOutputTokens: maxOutputTokens(for: operation),
            thinking: thinkingMode(for: operation)
        )
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw AIError.transport(String(describing: error.code))
        } catch {
            throw AIError.transport(String(describing: type(of: error)))
        }
        let text = try adapter.responseText(from: data, response: response)
#if DEBUG
        if operation == .decompose {
            let summary: String
            if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                let completion = json["completionStatus"] as? String ?? "missing"
                let candidates = (json["candidates"] as? [[String: Any]]) ?? []
                let anchorCount = candidates.reduce(0) {
                    $0 + (($1["sourceAnchors"] as? [[String: Any]])?.count ?? 0)
                }
                summary = "completion=\(completion) candidates=\(candidates.count) anchors=\(anchorCount)"
            } else {
                summary = "json=undecodable"
            }
            print("IF_IMPORT_RESPONSE chars=\(text.utf8.count) \(summary)")
        }
#endif
        guard let responseData = text.data(using: .utf8) else {
            throw AIError.invalidResponse("Provider content was not UTF-8")
        }
        if let response = try? decoder.decode(Response.self, from: responseData) {
            return response
        }

        // Some compatible providers still wrap structured output in a code
        // fence or add a short preamble despite being asked for JSON. Keep the
        // strict direct decode first, then salvage only the single JSON object
        // so the lazy first-answer request is not rejected for presentation
        // noise around an otherwise valid response.
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}"),
              firstBrace < lastBrace else {
            throw AIError.malformedStructuredResponse
        }
        let objectText = String(text[firstBrace...lastBrace])
        guard let objectData = objectText.data(using: .utf8),
              let response = try? decoder.decode(Response.self, from: objectData) else {
            throw AIError.malformedStructuredResponse
        }
        return response
    }

    private func maxOutputTokens(for operation: AIOperation) -> Int? {
        switch operation {
        case .decompose:
            // A chunk can contain several questions and every one carries a
            // quote/anchor, but the response must still fit in a bounded JSON
            // object. Leaving this unset lets DeepSeek spend the budget on
            // reasoning and return an incomplete/non-decodable object. The
            // larger real Markdown chunks can contain many candidates, so
            // allow enough room for the complete structured response.
            8_192
        case .evaluateScore:
            // DeepSeek V4 Flash defaults to thinking mode. Stage 1 is only a
            // numeric judgment, so it explicitly uses non-thinking mode and
            // needs only a small JSON budget.
            1_024
        case .evaluateFeedback:
            4_096
        case .referenceAnswer:
            2_048
        default:
            nil
        }
    }

    private func thinkingMode(for operation: AIOperation) -> AIThinkingMode? {
        // DeepSeek V4 Flash defaults to extended reasoning on both the Chat
        // Completions and the Responses API. Every operation is a structured
        // JSON transformation, and reasoning consumes the output budget
        // before any text is emitted (the relay reports
        // incomplete_details.reason = max_output_tokens). Keep reasoning
        // disabled so the importer gets a complete JSON object.
        guard configuration.provider == .openAICompatible
                || configuration.provider == .openAI,
              configuration.model.lowercased().hasPrefix("deepseek-v4-") else {
            return nil
        }
        return .disabled
    }
}
