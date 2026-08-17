import Foundation

struct BoundedAITaskResult<Output: Sendable>: Sendable {
    let index: Int
    let value: Output?
    let errorDescription: String?

    var succeeded: Bool {
        value != nil && errorDescription == nil
    }
}

enum BoundedAITaskRunner {
    static let defaultLimit = 3

    static func run<Input: Sendable, Output: Sendable>(
        inputs: [Input],
        limit: Int = defaultLimit,
        onResult: (@MainActor (BoundedAITaskResult<Output>) async -> Void)? = nil,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async -> [BoundedAITaskResult<Output>] {
        precondition(limit > 0)
        guard !inputs.isEmpty else { return [] }

        return await withTaskGroup(of: BoundedAITaskResult<Output>.self) { group in
            var nextIndex = 0
            let initialCount = min(limit, inputs.count)

            for index in 0..<initialCount {
                group.addTask {
                    await Self.execute(
                        index: index,
                        input: inputs[index],
                        operation: operation
                    )
                }
                nextIndex = index + 1
            }

            var results: [BoundedAITaskResult<Output>] = []
            results.reserveCapacity(inputs.count)
            while let result = await group.next() {
                results.append(result)
                if let onResult {
                    await onResult(result)
                }
                guard nextIndex < inputs.count else { continue }
                let index = nextIndex
                nextIndex += 1
                group.addTask {
                    await Self.execute(
                        index: index,
                        input: inputs[index],
                        operation: operation
                    )
                }
            }
            return results.sorted { $0.index < $1.index }
        }
    }

    private static func execute<Input: Sendable, Output: Sendable>(
        index: Int,
        input: Input,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async -> BoundedAITaskResult<Output> {
        do {
            return BoundedAITaskResult(
                index: index,
                value: try await operation(input),
                errorDescription: nil
            )
        } catch is CancellationError {
            return BoundedAITaskResult(
                index: index,
                value: nil,
                errorDescription: "CancellationError"
            )
        } catch {
            return BoundedAITaskResult(
                index: index,
                value: nil,
                errorDescription: String(describing: error)
            )
        }
    }
}
