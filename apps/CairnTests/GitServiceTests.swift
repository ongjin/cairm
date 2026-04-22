import XCTest
@testable import Cairn

final class GitServiceTests: XCTestCase {
    func test_non_repo_snapshot_is_nil() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let svc = GitService(root: d)
        XCTAssertNil(svc.snapshot)
    }

    func test_fresh_repo_snapshot_has_branch() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["git", "init", "-q", "-b", "main", d.path]
        try p.run(); p.waitUntilExit()

        let svc = GitService(root: d)
        XCTAssertNotNil(svc.snapshot)
        XCTAssertEqual(svc.snapshot?.branch, "main")
    }
}
