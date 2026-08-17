import Foundation
import SwiftData
import XCTest

final class TrashServiceTests: XCTestCase {
    func testExposedAudioCleanupRemovesStoredFile() throws {
        let fileManager = FileManager.default
        let relativePath = "trash-service-tests/\(UUID().uuidString).m4a"
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterviewFlashcard", isDirectory: true)
        let fileURL = base.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: fileURL)
        defer { try? fileManager.removeItem(at: fileURL.deletingLastPathComponent()) }

        let cleanup: TrashService.RemoveAudio = TrashService.removeAudioFile
        try cleanup(relativePath)

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path))
    }

    @MainActor
    func testTrashHidesAndRestoreRecoversCardWithHistory() throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let answer = try XCTUnwrap(card.referenceAnswers.first)
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: card.questionText,
            referenceAnswerTextSnapshot: answer.answerText,
            referenceAnswerVersion: 1,
            rawText: "回答",
            inputMode: .typed,
            startedAt: Fixtures.now,
            submittedAt: Fixtures.now,
            question: card
        )
        context.insert(attempt)
        try context.save()

        let service = TrashService(now: { Fixtures.now })
        try service.moveToTrash(cardID: card.id, context: context)
        XCTAssertNotNil(card.trashedAt)
        XCTAssertTrue(try HistoryQuery(context: context).global().isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).count, 1)

        try service.restore(cardID: card.id, context: context)
        XCTAssertNil(card.trashedAt)
        XCTAssertEqual(try HistoryQuery(context: context).global().count, 1)
    }

    @MainActor
    func testPermanentDeleteRemovesQuestionAndChildrenAfterSave() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context)
        let answer = try XCTUnwrap(card.referenceAnswers.first)
        let attempt = AnswerAttemptRecord(
            questionTextSnapshot: card.questionText,
            referenceAnswerTextSnapshot: answer.answerText,
            referenceAnswerVersion: 1,
            rawText: "回答",
            inputMode: .voice,
            startedAt: Fixtures.now,
            submittedAt: Fixtures.now,
            question: card
        )
        context.insert(attempt)
        context.insert(AudioAssetRecord(relativePath: "audio/test.m4a", duration: 1, byteCount: 1, checksum: "x", transcriptionEngine: "fixture", localeIdentifier: "zh-CN", attempt: attempt))
        try context.save()
        try TrashService(now: { Fixtures.now }).moveToTrash(cardID: card.id, context: context)

        let removed = RemovedAudioBox()
        let service = TrashService(now: { Fixtures.now }, removeAudio: { removed.paths.append($0) })
        try await service.permanentlyDelete(cardID: card.id, context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<QuestionCardRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).isEmpty)
        XCTAssertEqual(removed.paths, ["audio/test.m4a"])
    }
}

private final class RemovedAudioBox: @unchecked Sendable {
    var paths: [String] = []
}
