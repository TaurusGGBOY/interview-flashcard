import Foundation

protocol AIConnectionTesting: Sendable {
    func test(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String
}

struct AIConnectionTester: AIConnectionTesting {
    private let transport: any AIHTTPTransport
    private let timeout: TimeInterval

    init(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport(),
        timeout: TimeInterval = 30
    ) {
        self.transport = transport
        self.timeout = timeout
    }

    func test(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        let adapter = AIProviderAdapterFactory.make(for: configuration.provider)
        let request = try adapter.makeRequest(
            configuration: configuration,
            apiKey: apiKey,
            systemPrompt: "请简短回复。",
            userMessage: "你好",
            mode: .plainText,
            timeout: timeout,
            maxOutputTokens: nil,
            thinking: nil
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
        return try adapter.responseText(from: data, response: response)
    }
}
