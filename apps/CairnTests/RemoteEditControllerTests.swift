import XCTest
@testable import Cairn

private let stubTarget = SshTarget(user: "u", hostname: "h", port: 22, configHashHex: "test")

@MainActor
final class RemoteEditControllerTests: XCTestCase {
    func test_beginSession_downloadsAndRegistersSession() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("remote".utf8)])
        let controller = RemoteEditController(transfers: TransferController())

        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )

        XCTAssertEqual(try Data(contentsOf: session.tempURL), Data("remote".utf8))
        XCTAssertEqual(controller.activeSessions.count, 1)
        XCTAssertNotNil(controller.activeSessions[session.id])
    }

    func test_beginSession_rejectsFilesOver50MiB() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/huge": Data("x".utf8)])
        provider.setSize(path: "/tmp/huge", size: 50 * 1024 * 1024 + 1)
        let controller = RemoteEditController(transfers: TransferController())

        do {
            _ = try await controller.beginSession(
                remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/huge"),
                via: provider
            )
            XCTFail("Expected beginSession to reject huge files")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("too large"))
            XCTAssertTrue(controller.activeSessions.isEmpty)
        }
    }

    func test_upload_flagsConflictWhenRemoteMtimeAdvanced() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("remote".utf8)])
        let controller = RemoteEditController(transfers: TransferController())

        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )
        provider.setMtime(path: "/tmp/f", mtime: Date().addingTimeInterval(60))

        let outcome = try await controller.uploadSession(session.id, via: provider)
        XCTAssertEqual(outcome, .conflict)
        XCTAssertEqual(session.state, .conflict)
    }

    func test_localWrite_schedulesDebouncedUpload() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("orig".utf8)])
        let controller = RemoteEditController(transfers: TransferController())
        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )
        controller.armWatching(for: session.id, via: provider)
        try "edited".write(to: session.tempURL, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertEqual(provider.readSync("/tmp/f"), Data("edited".utf8))
        XCTAssertEqual(session.state, .done)
    }

    func test_localWrite_conflictResolverCanOverwriteRemote() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("orig".utf8)])
        let controller = RemoteEditController(transfers: TransferController())
        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )
        provider.setMtime(path: "/tmp/f", mtime: Date().addingTimeInterval(60))
        var resolverCalled = false

        controller.armWatching(for: session.id, via: provider) { conflictSession in
            resolverCalled = true
            XCTAssertEqual(conflictSession.id, session.id)
            return true
        }
        try "edited".write(to: session.tempURL, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertTrue(resolverCalled)
        XCTAssertEqual(provider.readSync("/tmp/f"), Data("edited".utf8))
        XCTAssertEqual(session.state, .done)
    }

    func test_endSession_removesTempDirAndStopsWatching() async throws {
        let provider = InMemoryFSProvider(files: ["/tmp/f": Data("orig".utf8)])
        let controller = RemoteEditController(transfers: TransferController())
        let session = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/f"),
            via: provider
        )
        let sessionDir = session.tempURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.path))

        controller.endSession(session.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.path))
        XCTAssertNil(controller.activeSessions[session.id])
    }

    func test_endSessionsForHost_removesOnlyMatchingHostSessions() async throws {
        let otherTarget = SshTarget(user: "u", hostname: "other", port: 22, configHashHex: "other")
        let provider = InMemoryFSProvider(files: [
            "/tmp/a": Data("a".utf8),
            "/tmp/b": Data("b".utf8),
        ])
        let controller = RemoteEditController(transfers: TransferController())
        let matching = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(stubTarget), path: "/tmp/a"),
            via: provider
        )
        let other = try await controller.beginSession(
            remotePath: FSPath(provider: .ssh(otherTarget), path: "/tmp/b"),
            via: provider
        )

        controller.endSessionsForHost(stubTarget)

        XCTAssertNil(controller.activeSessions[matching.id])
        XCTAssertNotNil(controller.activeSessions[other.id])
    }
}

final class InMemoryFSProvider: FileSystemProvider {
    var identifier: ProviderID { .ssh(stubTarget) }
    var displayScheme: String? { "stub" }
    var supportsServerSideCopy: Bool { false }

    private var files: [String: Data]
    private var mtimes: [String: Date] = [:]
    private var sizes: [String: Int64] = [:]

    init(files: [String: Data]) {
        self.files = files
    }

    func list(_ path: FSPath) async throws -> [FileEntry] { [] }

    func stat(_ path: FSPath) async throws -> FileStat {
        FileStat(
            size: sizes[path.path] ?? Int64(files[path.path]?.count ?? 0),
            mtime: mtimes[path.path] ?? Date(timeIntervalSince1970: 1_700_000_000),
            mode: 0o644,
            isDirectory: false
        )
    }

    func setMtime(path: String, mtime: Date) {
        mtimes[path] = mtime
    }

    func setSize(path: String, size: Int64) {
        sizes[path] = size
    }

    func readSync(_ path: String) -> Data {
        files[path] ?? Data()
    }

    func exists(_ path: FSPath) async throws -> Bool {
        files[path.path] != nil
    }

    func mkdir(_ path: FSPath) async throws {}
    func rename(from: FSPath, to: FSPath) async throws {}
    func delete(_ paths: [FSPath]) async throws {}
    func copyInPlace(from: FSPath, to: FSPath) async throws {}

    func readHead(_ path: FSPath, max: Int) async throws -> Data {
        files[path.path] ?? Data()
    }

    func downloadToCache(_ path: FSPath) async throws -> URL {
        tempFor(path)
    }

    func uploadFromLocal(_ localURL: URL,
                         to remotePath: FSPath,
                         progress: @escaping (Int64) -> Void,
                         cancel: CancelToken) async throws {
        files[remotePath.path] = try Data(contentsOf: localURL)
    }

    func downloadToLocal(_ remotePath: FSPath,
                         toLocalURL: URL,
                         progress: @escaping (Int64) -> Void,
                         cancel: CancelToken) async throws {
        try files[remotePath.path, default: Data()].write(to: toLocalURL)
    }

    func realpath(_ path: String) async throws -> String {
        path
    }

    private func tempFor(_ path: FSPath) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(path.lastComponent)
    }
}
