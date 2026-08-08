import XCTest

final class AppShellTests: XCTestCase {
    func testRootTabsHaveStableChineseTitles() {
        XCTAssertEqual(AppRoute.rootTabs.map(\.title), ["练习", "题库", "历史", "统计", "设置"])
        XCTAssertEqual(Set(AppRoute.rootTabs.map(\.accessibilityID)).count, 5)
    }

    func testColdLaunchStartsWithAnUnpracticedFeedAndCanRouteGlobalEmptyToLibrary() {
        let firstTopicID = UUID(uuidString: "73000000-0000-0000-0000-000000000001")!
        let state = PracticeView.initialFeedState(topicIDs: [firstTopicID])

        XCTAssertEqual(state.selectedTopicIDs, [firstTopicID])
        XCTAssertFalse(state.includePracticed)
        XCTAssertEqual(RootTabView.defaultSelection, .practice)
        XCTAssertEqual(RootTabView.globalEmptyDestination, .library)
    }

    func testAnswerEditorSubmissionRoutingUsesQuestionIDNotAttemptID() {
        let questionID = UUID(uuidString: "74000000-0000-0000-0000-000000000001")!
        let attemptID = UUID(uuidString: "75000000-0000-0000-0000-000000000001")!

        XCTAssertEqual(
            AnswerEditorView.submittedQuestionID(questionID: questionID, attemptID: attemptID),
            questionID
        )
        XCTAssertNotEqual(
            AnswerEditorView.submittedQuestionID(questionID: questionID, attemptID: attemptID),
            attemptID
        )
    }

    @MainActor
    func testDebugLaunchOptionsParseAcceptanceArguments() {
        let options = AppEnvironment.LaunchOptions.current(arguments: [
            "InterviewFlashcard",
            "-IFDiagnosticsEnabled", "YES",
            "-IFAIProvider", "stub",
            "-IFStubMode", "transient-failure",
            "-IFSpeechCapability", "unsupported",
            "-IFSeedFixture", "empty",
            "-IFRandomSeed", "42",
        ])

        #if DEBUG
        XCTAssertTrue(options.diagnosticsEnabled)
        XCTAssertEqual(options.aiProvider, .stub)
        XCTAssertEqual(options.stubMode, "transient-failure")
        XCTAssertEqual(options.speechCapability, .unsupported)
        XCTAssertEqual(options.seedFixture, "empty")
        XCTAssertEqual(options.randomSeed, 42)
        #else
        XCTAssertFalse(options.diagnosticsEnabled)
        XCTAssertEqual(options.aiProvider, .deepseek)
        XCTAssertNil(options.seedFixture)
        #endif
    }
}
