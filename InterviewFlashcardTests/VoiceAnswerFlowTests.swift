import Foundation
import SwiftData
import XCTest
@testable import InterviewFlashcard

final class VoiceAnswerFlowTests: XCTestCase {
    @MainActor
    func testSupportedFlowRecordsThenShowsEditableConfirmation() async throws {
        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportURL) }
        let recorder = FixtureAudioRecorder(applicationSupportURL: supportURL)
        let transcriber = FixtureSpeechTranscriber(
            capability: .available,
            transcript: SpeechTranscript(
                text: "JVM 会加载类",
                localeIdentifier: "zh-CN",
                confidenceSummary: "fixture"
            )
        )
        let controller = VoiceAnswerController(
            transcriber: transcriber,
            audioRecorder: recorder,
            locale: Locale(identifier: "zh-CN")
        )

        await controller.refreshCapability()
        XCTAssertEqual(controller.phase, .ready)
        await controller.startRecording()
        XCTAssertEqual(controller.phase, .recording)
        await controller.stopAndTranscribe()

        XCTAssertEqual(controller.phase, .confirmation)
        XCTAssertEqual(controller.transcriptText, "JVM 会加载类")
        controller.transcriptText = "JVM 会加载并验证类"
        let draft = try controller.audioAssetDraft()
        XCTAssertEqual(draft.relativePath.split(separator: "/").first, "Audio")
        XCTAssertEqual(draft.format, "m4a")
        XCTAssertEqual(draft.transcriptionEngine, "apple-speech-on-device")
        XCTAssertGreaterThan(draft.byteCount, 0)
        XCTAssertEqual(draft.checksum.count, 64)
    }

    @MainActor
    func testPermissionFailureDisablesVoiceAfterUserStartsFlow() async throws {
        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportURL) }
        let controller = VoiceAnswerController(
            transcriber: FixtureSpeechTranscriber(
                capability: .authorizationRequired,
                transcriptionError: .unavailable(.authorizationDenied)
            ),
            audioRecorder: FixtureAudioRecorder(applicationSupportURL: supportURL),
            locale: Locale(identifier: "zh-CN")
        )

        await controller.refreshCapability()
        XCTAssertEqual(controller.phase, .ready)
        await controller.startRecording()
        await controller.stopAndTranscribe()

        XCTAssertEqual(controller.phase, .unavailable)
        XCTAssertEqual(controller.capability, .unavailable(.authorizationDenied))
        XCTAssertFalse(controller.capability?.canStartVoiceAnswer ?? true)
    }

    @MainActor
    func testVoiceSubmissionRequiresConfirmedTextAndAudioThenPersistsBoth() async throws {
        let context = try TestModelContainer.make().mainContext
        let card = try Fixtures.makeCard(context: context, question: "JVM 如何加载类？")
        let scheduled = VoiceScheduleRecorder()
        let service = AnswerSubmissionService(
            now: { Fixtures.now.addingTimeInterval(60) },
            scheduleProcessing: { id in scheduled.record(id) }
        )
        let audio = AnswerSubmissionService.AudioAssetDraft(
            relativePath: "Audio/fixture.m4a",
            duration: 1.25,
            byteCount: 32,
            checksum: String(repeating: "a", count: 64),
            transcriptionEngine: "apple-speech-on-device",
            localeIdentifier: "zh-CN",
            confidenceSummary: "mean=0.900"
        )

        XCTAssertThrowsError(
            try service.submitVoice(
                questionID: card.id,
                confirmedText: "   ",
                audioAsset: audio,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? AnswerSubmissionService.SubmissionError, .emptyAnswer)
        }
        XCTAssertThrowsError(
            try service.submitVoice(
                questionID: card.id,
                confirmedText: "JVM 会加载类",
                audioAsset: nil,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? AnswerSubmissionService.SubmissionError, .missingAudioAsset)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<AnswerAttemptRecord>()).count, 0)

        let attempt = try service.submitVoice(
            questionID: card.id,
            confirmedText: "  JVM 会加载并验证类  ",
            audioAsset: audio,
            context: context
        )

        XCTAssertEqual(attempt.rawText, "JVM 会加载并验证类")
        XCTAssertEqual(attempt.inputMode, .voice)
        XCTAssertEqual(attempt.audioAsset?.relativePath, "Audio/fixture.m4a")
        XCTAssertEqual(attempt.audioAsset?.transcriptionEngine, "apple-speech-on-device")
        XCTAssertEqual(scheduled.ids, [attempt.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<AudioAssetRecord>()).count, 1)
    }

    @MainActor
    func testCancelRemovesUnsubmittedLocalDraft() async throws {
        let supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportURL) }
        let controller = VoiceAnswerController(
            transcriber: FixtureSpeechTranscriber(capability: .available),
            audioRecorder: FixtureAudioRecorder(applicationSupportURL: supportURL),
            locale: Locale(identifier: "zh-CN")
        )

        await controller.refreshCapability()
        await controller.startRecording()
        await controller.stopAndTranscribe()
        let fileURL = try XCTUnwrap(controller.recordedAudio?.fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        await controller.cancel()

        XCTAssertEqual(controller.phase, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

private final class VoiceScheduleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var ids: [UUID] = []

    func record(_ id: UUID) {
        lock.lock()
        ids.append(id)
        lock.unlock()
    }
}
