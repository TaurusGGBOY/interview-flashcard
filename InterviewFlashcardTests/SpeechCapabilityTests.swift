import Speech
import XCTest
@testable import InterviewFlashcard

final class SpeechCapabilityTests: XCTestCase {
    func testVoiceIsUnavailableWhenRecognizerCannotRunOnDevice() async {
        let transcriber = FixtureSpeechTranscriber(
            capability: .unavailable(.onDeviceModelMissing)
        )

        let enabled = await VoiceAvailability(transcriber: transcriber).isEnabled(
            locale: Locale(identifier: "zh-CN")
        )

        XCTAssertFalse(enabled)
    }

    func testAuthorizationCanOnlyBeRequestedAfterUserStartsVoiceFlow() async {
        let transcriber = FixtureSpeechTranscriber(capability: .authorizationRequired)

        let enabled = await VoiceAvailability(transcriber: transcriber).isEnabled(
            locale: Locale(identifier: "zh-CN")
        )

        XCTAssertTrue(enabled)
    }

    func testAppleRecognitionRequestAlwaysRequiresOnDeviceRecognition() {
        let request = SFSpeechURLRecognitionRequest(
            url: URL(fileURLWithPath: "/tmp/interview-flashcard-test.m4a")
        )

        AppleSpeechTranscriber.configureForLocalRecognition(request)

        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertFalse(request.shouldReportPartialResults)
    }

    func testUnavailableFixtureFailsClosedInsteadOfReturningText() async {
        let transcriber = FixtureSpeechTranscriber(
            capability: .unavailable(.onDeviceRecognitionUnsupported)
        )

        await XCTAssertThrowsErrorAsync(
            try await transcriber.transcribe(
                fileURL: URL(fileURLWithPath: "/tmp/never-uploaded.m4a"),
                locale: Locale(identifier: "zh-CN")
            )
        ) { error in
            XCTAssertEqual(
                error as? SpeechTranscriptionError,
                .unavailable(.onDeviceRecognitionUnsupported)
            )
        }
    }
}
