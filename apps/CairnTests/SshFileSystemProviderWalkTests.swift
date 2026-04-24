import XCTest
@testable import Cairn

@MainActor
final class SshFileSystemProviderWalkTests: XCTestCase {
    func test_walk_returnsNameMatches() async throws {
        guard let host = ProcessInfo.processInfo.environment["CAIRN_IT_SSH_HOST"] else {
            throw XCTSkip("no live host")
        }
        let pool = SshPoolService.forTesting()
        let target = try await pool.connect(
            hostAlias: host,
            overrides: ConnectSpecOverrides(
                user: ProcessInfo.processInfo.environment["CAIRN_IT_SSH_USER"],
                port: ProcessInfo.processInfo.environment["CAIRN_IT_SSH_PORT"].flatMap(UInt16.init),
                identityFile: ProcessInfo.processInfo.environment["CAIRN_IT_SSH_IDENTITY"],
                proxyCommand: nil,
                password: ProcessInfo.processInfo.environment["CAIRN_IT_SSH_PASSWORD"]
            )
        )
        defer { pool.disconnect(target) }
        let provider = SshFileSystemProvider(pool: pool, target: target, supportsServerSideCopy: false)
        var names: [String] = []

        let stream = provider.walk(
            root: FSPath(provider: .ssh(target), path: "/etc"),
            pattern: "conf",
            maxDepth: 3,
            cap: 50,
            includeHidden: false,
            cancel: CancelToken()
        )

        for try await entry in stream {
            names.append(entry.name.toString())
            if names.count == 50 { break }
        }

        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.allSatisfy { $0.lowercased().contains("conf") })
    }
}
