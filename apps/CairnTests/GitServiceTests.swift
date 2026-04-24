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
        try makeEmptyGitRepo(at: d, branch: "main")

        let svc = GitService(root: d)
        XCTAssertNotNil(svc.snapshot)
        XCTAssertEqual(svc.snapshot?.branch, "main")
    }

    /// Materialise the minimal `.git/` tree that libgit2 needs to treat `root`
    /// as a valid repository with an unborn HEAD pointing at `refs/heads/<branch>`.
    /// Used in place of spawning `/usr/bin/env git init` because the sandboxed
    /// Cairn test host can't invoke `xcrun`-resolved tools (`xcrun: error:
    /// cannot be used within an App Sandbox`).
    private func makeEmptyGitRepo(at root: URL, branch: String) throws {
        let fm = FileManager.default
        let git = root.appendingPathComponent(".git")
        for sub in ["objects/info", "objects/pack", "refs/heads", "refs/tags"] {
            try fm.createDirectory(at: git.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        try "ref: refs/heads/\(branch)\n"
            .write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let config = """
        [core]
        \trepositoryformatversion = 0
        \tfilemode = true
        \tbare = false
        \tlogallrefupdates = true
        """
        try config.write(to: git.appendingPathComponent("config"),
                         atomically: true, encoding: .utf8)
    }
}
