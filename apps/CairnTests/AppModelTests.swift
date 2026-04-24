import XCTest
import SwiftUI
@testable import Cairn

@MainActor
final class AppModelTests: XCTestCase {
    func test_initCreatesRemoteEditController() {
        let app = AppModel()

        XCTAssertTrue(app.remoteEdit.activeSessions.isEmpty)
    }

    func test_remoteEditChipCanBindToAppController() {
        let app = AppModel()

        _ = RemoteEditChip(controller: app.remoteEdit)
    }
}
