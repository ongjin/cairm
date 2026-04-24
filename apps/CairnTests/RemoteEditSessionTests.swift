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
}
