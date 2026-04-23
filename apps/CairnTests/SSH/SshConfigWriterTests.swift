import XCTest
@testable import Cairn

final class SshConfigWriterTests: XCTestCase {
    func testAppendCreatesBlock() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).config")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try SshConfigWriter.append(.init(
            nickname: "prod-api",
            hostname: "10.0.1.5",
            port: nil, user: "deploy",
            identityFile: "~/.ssh/id_ed25519",
            proxyCommand: nil
        ), to: tmp)
        let s = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(s.contains("Host prod-api"))
        XCTAssertTrue(s.contains("HostName 10.0.1.5"))
        XCTAssertTrue(s.contains("User deploy"))
        XCTAssertFalse(s.contains("Port "))   // default port omitted
    }

    func testPreservesExistingContent() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).config")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "Host staging\n    HostName 10.0.0.5\n".write(to: tmp, atomically: true, encoding: .utf8)
        try SshConfigWriter.append(.init(nickname: "prod", hostname: "1.2.3.4", port: nil, user: nil, identityFile: nil, proxyCommand: nil), to: tmp)
        let s = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(s.contains("Host staging"))
        XCTAssertTrue(s.contains("Host prod"))
    }

    func testRejectsInvalidNickname() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).config")
        XCTAssertThrowsError(try SshConfigWriter.append(.init(nickname: "has space", hostname: "x", port: nil, user: nil, identityFile: nil, proxyCommand: nil), to: tmp))
    }
}
