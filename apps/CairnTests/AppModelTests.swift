import XCTest
import SwiftUI
@testable import Cairn

@MainActor
final class AppModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Tab.disableBackgroundServicesForTests = true
    }

    override func tearDown() {
        Tab.disableBackgroundServicesForTests = false
        super.tearDown()
    }

    private func tmp() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_initCreatesRemoteEditController() {
        let app = AppModel()

        XCTAssertTrue(app.remoteEdit.activeSessions.isEmpty)
    }

    func test_remoteEditChipCanBindToAppController() {
        let app = AppModel()

        _ = RemoteEditChip(controller: app.remoteEdit)
    }

    func test_registerSceneUpdatesActiveScene() {
        let app = AppModel()
        let scene = WindowSceneModel(engine: app.engine, bookmarks: app.bookmarks, initialURL: tmp())

        app.register(scene: scene)

        XCTAssertTrue(app.activeScene === scene)
    }
}
