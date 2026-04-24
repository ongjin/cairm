import XCTest
@testable import Cairn

@MainActor
final class RemoteEditIntegrationTests: XCTestCase {
    func test_fullRoundtrip_uploadsEditedContent() async throws {
        let (pool, target, provider) = try await liveRemoteEditProvider()
        defer { pool.disconnect(target) }

        let localSeed = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-remote-edit-seed-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: localSeed) }

        let workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-remote-edit-work-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workRoot) }

        let remotePath = FSPath(
            provider: .ssh(target),
            path: "/tmp/cairn-remote-edit-\(UUID().uuidString).txt"
        )
        let original = Data("remote\n".utf8)
        let edited = Data("edited\n".utf8)
        try original.write(to: localSeed)

        var remoteCreated = false
        do {
            try await provider.uploadFromLocal(
                localSeed,
                to: remotePath,
                progress: { _ in },
                cancel: CancelToken()
            )
            remoteCreated = true

            let controller = RemoteEditController(
                transfers: TransferController(),
                workRoot: workRoot
            )
            let session = try await controller.beginSession(remotePath: remotePath, via: provider)
            XCTAssertEqual(try Data(contentsOf: session.tempURL), original)

            try edited.write(to: session.tempURL)
            let outcome = try await controller.uploadSession(session.id, via: provider)

            XCTAssertEqual(outcome, .uploaded)
            let remoteBytes = try await provider.readHead(remotePath, max: 64)
            XCTAssertEqual(remoteBytes, edited)
            controller.endSession(session.id)
            try? await provider.delete([remotePath])
        } catch {
            if remoteCreated {
                try? await provider.delete([remotePath])
            }
            throw error
        }
    }

    private func liveRemoteEditProvider() async throws -> (SshPoolService, SshTarget, SshFileSystemProvider) {
        guard let host = ProcessInfo.processInfo.environment["CAIRN_IT_SSH_HOST"] else {
            throw XCTSkip("CAIRN_IT_SSH_HOST not set")
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
        let provider = SshFileSystemProvider(pool: pool, target: target, supportsServerSideCopy: false)
        return (pool, target, provider)
    }
}
