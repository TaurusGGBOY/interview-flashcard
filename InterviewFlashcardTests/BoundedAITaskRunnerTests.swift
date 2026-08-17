import XCTest

final class BoundedAITaskRunnerTests: XCTestCase {
    func testRunsAllInputsWithConfiguredConcurrencyAndPreservesOrder() async {
        let counter = ActiveCallCounter()

        let results = await BoundedAITaskRunner.run(inputs: Array(0..<6), limit: 3) { value in
            await counter.started()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await counter.finished()
            return value * 2
        }

        XCTAssertEqual(results.compactMap(\.value), [0, 2, 4, 6, 8, 10])
        let maximumActive = await counter.maximumActive()
        XCTAssertLessThanOrEqual(maximumActive, 3)
    }

    func testCapturesIndividualFailureAndContinuesOtherInputs() async {
        let results = await BoundedAITaskRunner.run(inputs: Array(0..<4), limit: 2) { value in
            if value == 2 {
                throw TestFailure.injected
            }
            return value
        }

        XCTAssertEqual(results.compactMap(\.value), [0, 1, 3])
        let failure = results.first(where: { $0.index == 2 })
        XCTAssertNotNil(failure?.errorDescription)
    }

    func testReportsEachResultBeforeTheBatchReturns() async {
        let recorder = ResultRecorder()

        let results = await BoundedAITaskRunner.run(
            inputs: Array(0..<3),
            limit: 2,
            onResult: { result in
                await recorder.record(result.index)
            }
        ) { value in
            try? await Task.sleep(nanoseconds: UInt64(value + 1) * 10_000_000)
            return value
        }

        XCTAssertEqual(results.compactMap(\.value), [0, 1, 2])
        let recordedIndices = await recorder.indices()
        XCTAssertEqual(recordedIndices, [0, 1, 2])
    }
}

private actor ActiveCallCounter {
    private var active = 0
    private var maximum = 0

    func started() {
        active += 1
        maximum = max(maximum, active)
    }

    func finished() {
        active -= 1
    }

    func maximumActive() -> Int { maximum }
}

private actor ResultRecorder {
    private var recorded: [Int] = []

    func record(_ index: Int) {
        recorded.append(index)
    }

    func indices() -> [Int] { recorded.sorted() }
}

private enum TestFailure: Error {
    case injected
}
