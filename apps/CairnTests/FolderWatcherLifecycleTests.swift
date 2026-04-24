import XCTest
@testable import Cairn

final class FolderWatcherLifecycleTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func test_pause_suppressesEventsUntilResume() throws {
        let fireExpectation = XCTestExpectation(description: "event fired")
        fireExpectation.isInverted = true
        let resumedExpectation = XCTestExpectation(description: "event after resume")

        var pauseActive = true
        let watcher = FolderWatcher(root: dir) {
            if pauseActive {
                fireExpectation.fulfill()
            } else {
                resumedExpectation.fulfill()
            }
        }
        XCTAssertNotNil(watcher)
        watcher!.pause()

        let f = dir.appendingPathComponent("a.txt")
        try "x".write(to: f, atomically: true, encoding: .utf8)
        wait(for: [fireExpectation], timeout: 0.5)

        pauseActive = false
        watcher!.resume()

        let f2 = dir.appendingPathComponent("b.txt")
        try "y".write(to: f2, atomically: true, encoding: .utf8)
        wait(for: [resumedExpectation], timeout: 1.0)
    }
}
