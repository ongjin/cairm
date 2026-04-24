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
}

final class InMemoryFSProvider: FileSystemProvider {
    var identifier: ProviderID { .ssh(stubTarget) }
    var displayScheme: String? { "stub" }
    var supportsServerSideCopy: Bool { false }

    private var files: [String: Data]

    init(files: [String: Data]) {
        self.files = files
    }

    func list(_ path: FSPath) async throws -> [FileEntry] { [] }

    func stat(_ path: FSPath) async throws -> FileStat {
        FileStat(
            size: Int64(files[path.path]?.count ?? 0),
            mtime: Date(timeIntervalSince1970: 1_700_000_000),
            mode: 0o644,
            isDirectory: false
        )
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
