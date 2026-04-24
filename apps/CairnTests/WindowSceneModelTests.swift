import XCTest
@testable import Cairn

final class WindowSceneModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Tab.disableBackgroundServicesForTests = true
    }

    override func tearDown() {
        Tab.disableBackgroundServicesForTests = false
        super.tearDown()
    }

    /// IndexService indexes the entire subtree synchronously on init, so we
    /// steer Tab at isolated temp directories rather than `/tmp` directly.
    private func tmp() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowSceneModelTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func makeScene() -> WindowSceneModel {
        let bookmarks = BookmarkStore(storageDirectory: tmp())
        return WindowSceneModel(
            engine: CairnEngine(),
            bookmarks: bookmarks,
            initialURL: tmp()
        )
    }

    func test_initial_has_one_tab() {
        let m = makeScene()
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTab)
    }

    func test_newTab_appends_and_activates() {
        let m = makeScene()
        let cloneRoot = tmp()
        defer { try? FileManager.default.removeItem(at: cloneRoot) }
        m.tabs[0].history = NavigationHistory()
        m.tabs[0].history.push(FSPath(provider: .local, path: cloneRoot.path))
        m.newTab()
        XCTAssertEqual(m.tabs.count, 2)
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }

    func test_closeTab_picks_remaining_tab() {
        let m = makeScene()
        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "close")
        m.newRemoteTab(
            initialPath: FSPath(provider: .ssh(target), path: "/workspace"),
            provider: TestRemoteProvider(target: target)
        )
        let closedID = m.tabs[1].id
        m.closeTab(closedID)
        XCTAssertEqual(m.tabs.count, 1)
        XCTAssertNotNil(m.activeTabID)
        XCTAssertNotEqual(m.activeTabID, closedID)
    }

    @MainActor
    func test_closeRemoteTab_endsRemoteEditSessionsForHost() async throws {
        let m = makeScene()
        let app = AppModel()
        m.app = app
        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "remote-edit")
        let provider = TestRemoteProvider(target: target, files: ["/workspace/f": Data("remote".utf8)])
        m.newRemoteTab(
            initialPath: FSPath(provider: .ssh(target), path: "/workspace"),
            provider: provider
        )
        let closedID = m.tabs[1].id
        let session = try await app.remoteEdit.beginSession(
            remotePath: FSPath(provider: .ssh(target), path: "/workspace/f"),
            via: provider
        )

        m.closeTab(closedID)

        XCTAssertNil(app.remoteEdit.activeSessions[session.id])
    }

    func test_activatePrevious_wraps() {
        let m = makeScene()
        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "prev")
        m.newRemoteTab(
            initialPath: FSPath(provider: .ssh(target), path: "/workspace"),
            provider: TestRemoteProvider(target: target)
        )
        m.activateTab(at: 0)
        m.activatePrevious()
        XCTAssertEqual(m.activeTabID, m.tabs[1].id)
    }

    func test_activeTab_switch_reconciles_tabActiveFlags() {
        let m = makeScene()
        XCTAssertTrue(m.tabs[0].isActive)

        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "deadbeef")
        let provider = TestRemoteProvider(target: target)
        m.newRemoteTab(
            initialPath: FSPath(provider: .ssh(target), path: "/workspace"),
            provider: provider
        )
        XCTAssertFalse(m.tabs[0].isActive)
        XCTAssertTrue(m.tabs[1].isActive)

        m.activateTab(at: 0)
        XCTAssertTrue(m.tabs[0].isActive)
        XCTAssertFalse(m.tabs[1].isActive)
    }
}

private final class TestRemoteProvider: FileSystemProvider {
    let identifier: ProviderID
    let displayScheme: String? = "ssh"
    let supportsServerSideCopy: Bool = false
    private var files: [String: Data]

    init(target: SshTarget, files: [String: Data] = [:]) {
        self.identifier = .ssh(target)
        self.files = files
    }

    func list(_ path: FSPath) async throws -> [FileEntry] { [] }
    func stat(_ path: FSPath) async throws -> FileStat {
        let data = files[path.path]
        return FileStat(size: Int64(data?.count ?? 0), mtime: nil, mode: 0, isDirectory: data == nil)
    }
    func exists(_ path: FSPath) async throws -> Bool { true }
    func mkdir(_ path: FSPath) async throws {}
    func rename(from: FSPath, to: FSPath) async throws {}
    func delete(_ paths: [FSPath]) async throws {}
    func copyInPlace(from: FSPath, to: FSPath) async throws {}
    func readHead(_ path: FSPath, max: Int) async throws -> Data { Data() }
    func downloadToCache(_ path: FSPath) async throws -> URL { URL(fileURLWithPath: "/tmp") }
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        files[remotePath.path] = try Data(contentsOf: localURL)
    }
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        try files[remotePath.path, default: Data()].write(to: toLocalURL)
    }
    func realpath(_ path: String) async throws -> String { path }
}
