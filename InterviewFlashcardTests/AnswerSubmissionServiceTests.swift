import SwiftData
import XCTest

final class AnswerSubmissionServiceTests: XCTestCase {
    @MainActor
    func testTextSubmissionSavesImmutableSnapshotsBeforeScheduling() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, question: "什么是 JVM 类加载？")
        let submittedAt = Fixtures.now.addingTimeInterval(120)
        let recorder = ScheduleRecorder()
        let service = AnswerSubmissionService(
            now: { submittedAt },
            scheduleProcessing: { id in recorder.record(id) }
        )

        let attempt = try service.submitText(
            questionID: card.id,
            rawText: "  JVM 会加载 class 并做验证  ",
            context: context
        )

        XCTAssertEqual(attempt.rawText, "JVM 会加载 class 并做验证")
        XCTAssertEqual(attempt.inputMode, .typed)
        XCTAssertEqual(attempt.questionTextSnapshot, "什么是 JVM 类加载？")
        XCTAssertEqual(attempt.referenceAnswerVersion, 1)
        XCTAssertEqual(recorder.ids, [attempt.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AudioAssetRecord>()).count, 0)
    }

    @MainActor
    func testBlankAndTrashedQuestionAreRejectedWithoutCreatingAttempt() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let service = AnswerSubmissionService(now: { Fixtures.now })

        XCTAssertThrowsError(try service.submitText(questionID: card.id, rawText: " \n", context: context)) { error in
            XCTAssertEqual(error as? AnswerSubmissionService.SubmissionError, .emptyAnswer)
        }
        card.trashedAt = Fixtures.now
        try context.save()
        XCTAssertThrowsError(try service.submitText(questionID: card.id, rawText: "有内容", context: context)) { error in
            XCTAssertEqual(error as? AnswerSubmissionService.SubmissionError, .questionNotFound)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).count, 0)
    }

    @MainActor
    func testSubmissionDoesNotWaitForMissingReferenceAnswer() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, includeReferenceAnswer: false)

        let attempt = try AnswerSubmissionService().submitText(
            questionID: card.id,
            rawText: "先给出核心机制，再说明边界。",
            context: context
        )

        XCTAssertEqual(attempt.referenceAnswerVersion, 0)
        XCTAssertTrue(attempt.referenceAnswerTextSnapshot.isEmpty)
        XCTAssertEqual(attempt.processingStatus, .saved)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AudioAssetRecord>()).count, 0)
    }
}

private final class ScheduleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        lock.lock()
        ids.append(id)
        lock.unlock()
    }
}
