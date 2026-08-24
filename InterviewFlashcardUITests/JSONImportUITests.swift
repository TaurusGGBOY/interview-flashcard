import XCTest

@MainActor
final class JSONImportUITests: XCTestCase {
    func testJSONTemplateIsDiscoverableFromImportScreen() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
        ]
        app.launch()

        let libraryTab = app.tabBars.buttons["题库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5))
        libraryTab.tap()

        let openImport = app.buttons["library.import-markdown"]
        XCTAssertTrue(openImport.waitForExistence(timeout: 5))
        openImport.tap()

        let templateButton = app.buttons["import.json.template-button"]
        XCTAssertTrue(templateButton.waitForExistence(timeout: 5))
        templateButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["import.json.template"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["import.json.template.code"].exists)
        XCTAssertTrue(app.buttons["import.json.template.copy"].exists)
    }

    func testJSONInboxLaunchOptionImportsWithoutUIInteraction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
            "-IFDiagnosticsEnabled", "YES",
            "-IFAcceptanceJSONFixtureFile", "acceptance-json-launch.json",
            "-IFJSONInboxImport", "YES",
        ]
        app.launch()

        let libraryTab = app.tabBars.buttons["题库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 15))
        libraryTab.tap()

        let openImport = app.buttons["library.import-markdown"]
        XCTAssertTrue(openImport.waitForExistence(timeout: 15))
        openImport.tap()

        XCTAssertTrue(app.staticTexts["JSON · 已导入 3 道题目"].waitForExistence(timeout: 15))
    }

    func testJSONInboxCanBePreviewedAndImportedWithoutOpeningFilePicker() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
            "-IFAcceptanceJSONFixtureFile", "acceptance-json-inbox.json",
        ]
        app.launch()

        let libraryTab = app.tabBars.buttons["题库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5))
        libraryTab.tap()

        let openImport = app.buttons["library.import-markdown"]
        XCTAssertTrue(openImport.waitForExistence(timeout: 5))
        openImport.tap()

        let inboxImport = app.buttons["import.json.inbox-button"]
        XCTAssertTrue(inboxImport.waitForExistence(timeout: 5))
        inboxImport.tap()

        let preview = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ OR identifier == %@",
                "import.json.preview",
                "import.json.batch-preview"
            )
        ).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))

        let batchConfirm = app.buttons["import.json.batch-confirm"]
        let confirm = batchConfirm.waitForExistence(timeout: 1)
            ? batchConfirm
            : app.buttons["import.json.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.staticTexts["JSON · 已导入 3 道题目"].waitForExistence(timeout: 10))
    }

    func testJSONFileCanBePreviewedImportedAndOpened() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-IFAIProvider", "stub",
            "-IFSeedFixture", "practice-mixed",
            "-IFAcceptanceJSONFixtureFile", "acceptance-json-import.json",
        ]
        app.launch()

        let libraryTab = app.tabBars.buttons["题库"]
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 5))
        libraryTab.tap()

        let openImport = app.buttons["library.import-markdown"]
        XCTAssertTrue(openImport.waitForExistence(timeout: 5))
        openImport.tap()

        let jsonImport = app.buttons["import.json.button"]
        XCTAssertTrue(jsonImport.waitForExistence(timeout: 5))
        jsonImport.tap()

        selectFixture(named: "acceptance-json-import.json", in: app)

        let preview = app.descendants(matching: .any)["import.json.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["JSON 校验已通过"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "共有 3 道题目")
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "JSON 新主题")
            ).firstMatch.exists
        )
        addScreenshot(named: "json-import-preview", app: app)

        let confirm = app.buttons["import.json.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let completedSummary = app.staticTexts["JSON · 已导入 3 道题目"]
        XCTAssertTrue(completedSummary.waitForExistence(timeout: 10))
        addScreenshot(named: "json-import-completed", app: app)

        let viewCards = app.buttons["查看生成题目"].firstMatch
        XCTAssertTrue(viewCards.waitForExistence(timeout: 5))
        viewCards.tap()

        let duplicateCards = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "JSON 验收题目：重复题")
        )
        XCTAssertTrue(waitForCount(2, in: duplicateCards))
        XCTAssertEqual(duplicateCards.count, 2)
        addScreenshot(named: "json-imported-cards", app: app)

        let existingTopicCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "JSON 验收题目：已有 Topic")
        ).firstMatch
        XCTAssertTrue(existingTopicCard.waitForExistence(timeout: 5))
        existingTopicCard.tap()
        let importedAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "第一行满分答案")
        ).firstMatch
        XCTAssertTrue(importedAnswer.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "第二行用于验证多行内容")
            ).firstMatch.exists
        )
        addScreenshot(named: "json-imported-answer", app: app)
    }

    private func selectFixture(named fileName: String, in app: XCUIApplication) {
        let file = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", fileName, fileName)
        ).firstMatch

        if file.waitForExistence(timeout: 5) {
            file.tap()
            return
        }

        tapFirstExisting(labels: ["浏览", "Browse"], in: app)
        tapFirstExisting(labels: ["我的iPhone", "我的 iPhone", "On My iPhone"], in: app)
        tapFirstExisting(labels: ["面试闪卡", "InterviewFlashcard"], in: app)

        XCTAssertTrue(file.waitForExistence(timeout: 5), "文件选择器中没有找到 \(fileName)")
        file.tap()
    }

    private func tapFirstExisting(labels: [String], in app: XCUIApplication) {
        for label in labels {
            let exact = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", label)
            ).firstMatch
            if exact.waitForExistence(timeout: 1) {
                exact.tap()
                return
            }
        }
    }

    private func waitForCount(_ expected: Int, in query: XCUIElementQuery) -> Bool {
        let predicate = NSPredicate { _, _ in query.count == expected }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func addScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
