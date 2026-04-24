import XCTest
@testable import Cairn

final class UpdaterServiceTests: XCTestCase {
    func test_feedURL_defaultsToPublicAppcast() {
        XCTAssertEqual(
            UpdaterService.feedURL.absoluteString,
            "https://github.com/ongjin/cairn/releases/latest/download/appcast.xml"
        )
    }
}
