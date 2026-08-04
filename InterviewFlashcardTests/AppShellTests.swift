import XCTest
@testable import InterviewFlashcard

final class AppShellTests: XCTestCase {
    func testRootTabsHaveStableChineseTitles() {
        XCTAssertEqual(AppRoute.rootTabs.map(\.title), ["练习", "题库", "历史", "统计", "设置"])
        XCTAssertEqual(Set(AppRoute.rootTabs.map(\.accessibilityID)).count, 5)
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
