import Foundation

struct RetryingAIClient: AIClient {
    typealias Sleeper = @Sendable (_ nanoseconds: UInt64) async throws -> Void

    private let base: any AIClient
    private let maximumRetries: Int
    private let retryDelayNanoseconds: UInt64
    private let sleeper: Sleeper

    init(
        base: any AIClient,
        maximumRetries: Int = 1,
        retryDelayNanoseconds: UInt64 = 300_000_000,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.base = base
        self.maximumRetries = max(0, maximumRetries)
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.sleeper = sleeper
    }

    func decompose(_ request: DecomposeRequest) async throws -> DecomposeResponse {
        try await execute { try await base.decompose(request) }
    }

    func refine(_ request: RefineRequest) async throws -> RefineResponse {
        try await execute { try await base.refine(request) }
    }

    func reclassify(_ request: ReclassifyRequest) async throws -> ReclassifyResponse {
        try await execute { try await base.reclassify(request) }
    }

    func polish(_ request: PolishRequest) async throws -> PolishResponse {
        try await execute { try await base.polish(request) }
    }

    func evaluate(_ request: EvaluationRequest) async throws -> EvaluationResponse {
        try await execute { try await base.evaluate(request) }
    }

    private func execute<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        var retryCount = 0
        while true {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard retryCount < maximumRetries, isTransient(error) else {
                    throw error
                }
                retryCount += 1
                if retryDelayNanoseconds > 0 {
                    try await sleeper(retryDelayNanoseconds)
                }
            }
        }
    }

    private func isTransient(_ error: Error) -> Bool {
        if let aiError = error as? AIError {
            return aiError.isTransient
        }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .notConnectedToInternet
            ].contains(urlError.code)
        }
        return false
    }
}
