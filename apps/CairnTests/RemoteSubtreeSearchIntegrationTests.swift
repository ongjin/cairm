import Foundation
import XCTest
@testable import Cairn

@MainActor
final class RemoteSubtreeSearchIntegrationTests: XCTestCase {
    private struct LiveFixture {
        let root: FSPath
        let files: [FSPath]
    }

    func test_subtreeSearch_respectsCapAndCancel() async throws {
        let (pool, target, provider) = try await liveProvider()
        defer { pool.disconnect(target) }

        let fixture = try await uploadFixtureTree(provider: provider, target: target)

        let model = SearchModel(engine: CairnEngine(), remoteSubtreeResultCap: 10)
        model.query = "foo_"
        model.scope = .subtree
        model.refresh(
            root: fixture.root,
            provider: provider,
            showHidden: false,
            sort: .init(field: .name, order: .ascending),
            folderEntries: []
        )

        for _ in 0..<200 where model.phase == .running {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(model.results.count, 10)
        XCTAssertEqual(model.hitCount, 10)
        XCTAssertEqual(model.phase, .capped)
        XCTAssertTrue(model.results.allSatisfy { $0.name.toString().contains("foo_") })

        let canceling = SearchModel(engine: CairnEngine(), remoteSubtreeResultCap: 10_000)
        canceling.query = "foo_"
        canceling.scope = .subtree
        canceling.refresh(
            root: fixture.root,
            provider: provider,
            showHidden: false,
            sort: .init(field: .name, order: .ascending),
            folderEntries: []
        )
        canceling.clear()

        XCTAssertEqual(canceling.phase, .idle)
        XCTAssertTrue(canceling.results.isEmpty)
        XCTAssertEqual(canceling.hitCount, 0)

        await cleanupFixture(fixture, provider: provider)
    }

    private func liveProvider() async throws -> (SshPoolService, SshTarget, SshFileSystemProvider) {
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

    private func uploadFixtureTree(provider: SshFileSystemProvider, target: SshTarget) async throws -> LiveFixture {
        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-remote-subtree-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: localRoot) }

        let remoteRoot = "/tmp/cairn-remote-subtree-search-\(UUID().uuidString)"
        let root = FSPath(provider: .ssh(target), path: remoteRoot)
        let nested = FSPath(provider: .ssh(target), path: "\(remoteRoot)/nested")
        try await provider.mkdir(root)
        try await provider.mkdir(nested)

        var files: [FSPath] = []
        for i in 0..<50 {
            let name = String(format: "foo_%03d.txt", i)
            let local = localRoot.appendingPathComponent(name)
            try Data("fixture \(i)\n".utf8).write(to: local)

            let parent = i.isMultiple(of: 2) ? remoteRoot : "\(remoteRoot)/nested"
            let remote = FSPath(provider: .ssh(target), path: "\(parent)/\(name)")
            try await provider.uploadFromLocal(local, to: remote, progress: { _ in }, cancel: CancelToken())
            files.append(remote)
        }

        return LiveFixture(root: root, files: files)
    }

    private func cleanupFixture(_ fixture: LiveFixture, provider: SshFileSystemProvider) async {
        for file in fixture.files {
            try? await provider.delete([file])
        }
    }
}
