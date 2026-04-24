import Foundation
import XCTest
@testable import Cairn

@MainActor
final class FolderCompareIntegrationTests: XCTestCase {
    func test_compareLocalToRemote_detectsOnlyRightEntries() async throws {
        let (pool, target, remoteProvider) = try await liveFolderCompareProvider()
        defer { pool.disconnect(target) }

        let localRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-folder-compare-local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: localRootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: localRootURL) }

        let sharedLocal = localRootURL.appendingPathComponent("shared.txt")
        try Data("shared\n".utf8).write(to: sharedLocal)

        let remoteOnlySeed = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-folder-compare-remote-only-\(UUID().uuidString).txt")
        try Data("remote-only\n".utf8).write(to: remoteOnlySeed)
        defer { try? FileManager.default.removeItem(at: remoteOnlySeed) }

        let remoteRoot = FSPath(
            provider: .ssh(target),
            path: "/tmp/cairn-folder-compare-\(UUID().uuidString)"
        )
        let remoteShared = FSPath(provider: .ssh(target), path: "\(remoteRoot.path)/shared.txt")
        let remoteOnly = FSPath(provider: .ssh(target), path: "\(remoteRoot.path)/remote-only.txt")
        var cleanupPaths: [FSPath] = []

        do {
            try await remoteProvider.mkdir(remoteRoot)
            cleanupPaths.append(remoteRoot)

            try await remoteProvider.uploadFromLocal(
                sharedLocal,
                to: remoteShared,
                progress: { _ in },
                cancel: CancelToken()
            )
            cleanupPaths.append(remoteShared)

            try await remoteProvider.uploadFromLocal(
                remoteOnlySeed,
                to: remoteOnly,
                progress: { _ in },
                cancel: CancelToken()
            )
            cleanupPaths.append(remoteOnly)

            let localProvider = LocalFileSystemProvider(engine: CairnEngine())
            let result = try await FolderCompare.compareRecursive(
                leftRoot: localRootURL.path,
                leftProvider: localProvider,
                rightRoot: remoteRoot.path,
                rightProvider: remoteProvider,
                mode: .nameSize,
                cancel: CancelToken()
            )

            XCTAssertEqual(Set(result.onlyRight.map(\.name)), Set(["remote-only.txt"]))
            XCTAssertTrue(result.same.map(\.name).contains("shared.txt"))

            await cleanupRemote(paths: cleanupPaths.reversed(), provider: remoteProvider)
        } catch {
            await cleanupRemote(paths: cleanupPaths.reversed(), provider: remoteProvider)
            throw error
        }
    }

    private func liveFolderCompareProvider() async throws -> (SshPoolService, SshTarget, SshFileSystemProvider) {
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
        let provider = SshFileSystemProvider(pool: pool, target: target, supportsServerSideCopy: false)
        return (pool, target, provider)
    }

    private func cleanupRemote(paths: ReversedCollection<[FSPath]>, provider: SshFileSystemProvider) async {
        for path in paths {
            try? await provider.delete([path])
        }
    }
}
