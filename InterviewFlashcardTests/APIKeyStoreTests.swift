import XCTest
@testable import InterviewFlashcard

final class APIKeyStoreTests: XCTestCase {
    func testInMemoryStoreSupportsSaveUpdateLoadAndDelete() throws {
        let store = InMemoryAPIKeyStore()

        XCTAssertNil(try store.load())
        try store.save("first-secret")
        XCTAssertEqual(try store.load(), "first-secret")
        try store.save("replacement-secret")
        XCTAssertEqual(try store.load(), "replacement-secret")
        try store.delete()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.delete())
    }

    func testInMemoryStoreRejectsBlankKey() {
        let store = InMemoryAPIKeyStore()

        XCTAssertThrowsError(try store.save("  \n")) { error in
            XCTAssertEqual(error as? APIKeyStoreError, .emptyKey)
        }
        XCTAssertNil(try store.load())
    }

    func testKeychainUsesStableServiceAndAccountWithoutReadingRealKeychain() {
        XCTAssertEqual(KeychainAPIKeyStore.service, "com.gaoguobin.InterviewFlashcard.deepseek")
        XCTAssertEqual(KeychainAPIKeyStore.account, "api-key")
    }
}
