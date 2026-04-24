import XCTest
@testable import Cairn

@MainActor
final class AppModelTests: XCTestCase {
    func test_initCreatesRemoteEditController() {
        let app = AppModel()

        XCTAssertTrue(app.remoteEdit.activeSessions.isEmpty)
    }
}
