import XCTest
@testable import Cairn

final class EmptyStateViewTests: XCTestCase {
    func test_emptyFolder_uses_folder_icon_and_correct_title() {
        let v = EmptyStateView.emptyFolder()
        XCTAssertEqual(v.icon, "folder")
        XCTAssertEqual(v.title, "Empty folder")
        XCTAssertEqual(v.subtitle, "No files here.")
        XCTAssertNil(v.action)
    }

    func test_searchNoMatch_includes_query_in_subtitle() {
        let v = EmptyStateView.searchNoMatch(query: "hello")
        XCTAssertEqual(v.icon, "magnifyingglass")
        XCTAssertEqual(v.title, "No matches")
        XCTAssertEqual(v.subtitle, "for \"hello\"")
    }

    func test_permissionDenied_has_retry_action() {
        var called = false
        let v = EmptyStateView.permissionDenied(onRetry: { called = true })
        XCTAssertEqual(v.icon, "lock")
        XCTAssertEqual(v.title, "Can't read this folder")
        XCTAssertNotNil(v.action)
        v.action?.perform()
        XCTAssertTrue(called)
    }

    func test_permissionDenied_custom_message_sets_subtitle() {
        let v = EmptyStateView.permissionDenied(message: "No such directory") {}
        XCTAssertEqual(v.subtitle, "No such directory")
    }
}
