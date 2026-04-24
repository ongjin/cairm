import XCTest
@testable import Cairn

final class RemoteEditSessionTests: XCTestCase {
    func test_init_capturesRemoteMtimeAndTempURL() {
        let target = SshTarget(user: "u", hostname: "h", port: 22, configHashHex: "test")
        let remote = FSPath(provider: .ssh(target), path: "/etc/hosts")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteEditSessionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let session = RemoteEditSession(
            remotePath: remote,
            tempURL: tempDir.appendingPathComponent("hosts"),
            remoteMtimeAtDownload: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(session.remotePath, remote)
        XCTAssertEqual(session.tempURL.lastPathComponent, "hosts")
        XCTAssertEqual(session.remoteMtimeAtDownload,
                       Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(session.state, .watching)
    }

    func test_watcher_firesOnFileWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteEditSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("f.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let session = RemoteEditSession(
            remotePath: FSPath(
                provider: .ssh(SshTarget(user: "u", hostname: "h", port: 22, configHashHex: "test")),
                path: "/tmp/f.txt"
            ),
            tempURL: fileURL,
            remoteMtimeAtDownload: Date()
        )

        let expect = expectation(description: "watcher fires")
        session.onLocalChange = { expect.fulfill() }
        session.startWatching()

        try "world".write(to: fileURL, atomically: true, encoding: .utf8)

        wait(for: [expect], timeout: 2.0)
        session.stopWatching()
    }
}
