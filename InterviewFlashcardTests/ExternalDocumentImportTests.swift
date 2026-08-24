import XCTest

final class ExternalDocumentImportTests: XCTestCase {
    func testClassifiesMarkdownJSONAndUnsupportedFilesCaseInsensitively() {
        let urls = [
            URL(fileURLWithPath: "/tmp/go.MD"),
            URL(fileURLWithPath: "/tmp/questions.JSON"),
            URL(fileURLWithPath: "/tmp/notes.txt"),
        ]

        let result = ExternalDocumentImportRouter.classify(urls: urls)

        XCTAssertEqual(result.markdown.map(\.lastPathComponent), ["go.MD"])
        XCTAssertEqual(result.json.map(\.lastPathComponent), ["questions.JSON"])
        XCTAssertEqual(result.unsupported.map(\.lastPathComponent), ["notes.txt"])
    }

    func testClassificationPreservesInputOrder() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.json"),
            URL(fileURLWithPath: "/tmp/a.md"),
            URL(fileURLWithPath: "/tmp/b.json"),
            URL(fileURLWithPath: "/tmp/b.md"),
        ]

        let result = ExternalDocumentImportRouter.classify(urls: urls)

        XCTAssertEqual(result.json.map(\.lastPathComponent), ["a.json", "b.json"])
        XCTAssertEqual(result.markdown.map(\.lastPathComponent), ["a.md", "b.md"])
    }

    @MainActor
    func testInboxDeduplicatesDuplicateDeliveryButAllowsNewFiles() {
        let inbox = ExternalDocumentImportInbox()
        let first = URL(fileURLWithPath: "/tmp/questions.json")
        let second = URL(fileURLWithPath: "/tmp/notes.md")

        inbox.receive([first, first])
        XCTAssertEqual(inbox.pendingRequest?.urls, [first])

        inbox.receive([first, second])
        XCTAssertEqual(inbox.pendingRequest?.urls, [first, second])
    }

    func testApplicationPlistDeclaresJSONAndMarkdownDocumentTypes() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = projectRoot
            .appendingPathComponent("InterviewFlashcard/App/InterviewFlashcard-Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: plistURL)) as! [String: Any]
        let documentTypes = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = documentTypes
            .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }

        XCTAssertTrue(contentTypes.contains("public.json"))
        XCTAssertTrue(contentTypes.contains("com.gaoguobin.interview-flashcard.markdown"))

        let exportedTypes = try XCTUnwrap(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let markdown = try XCTUnwrap(
            exportedTypes.first { $0["UTTypeIdentifier"] as? String == "com.gaoguobin.interview-flashcard.markdown" }
        )
        XCTAssertEqual(markdown["UTTypeConformsTo"] as? [String], ["public.text"])
        let tags = try XCTUnwrap(markdown["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["md"])
    }
}
