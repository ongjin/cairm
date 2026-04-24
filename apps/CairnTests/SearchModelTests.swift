import XCTest
@testable import Cairn

final class SearchModelTests: XCTestCase {
    private func engine() -> CairnEngine { CairnEngine() }
    private func localRoot(_ path: String = "/") -> FSPath {
        FSPath(provider: .local, path: path)
    }
    private func localProvider() -> FileSystemProvider {
        LocalFileSystemProvider(engine: engine())
    }

    private final class RecordingWalkProvider: FileSystemProvider {
        struct WalkCall {
            let root: FSPath
            let pattern: String
            let maxDepth: Int
            let cap: Int
            let includeHidden: Bool
        }

        let identifier: ProviderID
        let displayScheme: String? = "ssh://"
        let supportsServerSideCopy = false
        var walkCalls: [WalkCall] = []
        var entries: [FileEntry] = []
        var holdOpen = false
        var lastCancel: CancelToken?

        init(target: SshTarget) {
            self.identifier = .ssh(target)
        }

        func list(_ path: FSPath) async throws -> [FileEntry] { [] }
        func stat(_ path: FSPath) async throws -> FileStat {
            FileStat(size: 0, mtime: nil, mode: 0, isDirectory: false)
        }
        func exists(_ path: FSPath) async throws -> Bool { false }
        func mkdir(_ path: FSPath) async throws {}
        func rename(from: FSPath, to: FSPath) async throws {}
        func delete(_ paths: [FSPath]) async throws {}
        func copyInPlace(from: FSPath, to: FSPath) async throws {}
        func readHead(_ path: FSPath, max: Int) async throws -> Data { Data() }
        func downloadToCache(_ path: FSPath) async throws -> URL { URL(fileURLWithPath: "/tmp") }
        func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {}
        func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {}
        func realpath(_ path: String) async throws -> String { path }

        func walk(
            root: FSPath,
            pattern: String,
            maxDepth: Int,
            cap: Int,
            includeHidden: Bool,
            cancel: CancelToken
        ) -> AsyncThrowingStream<FileEntry, Error> {
            lastCancel = cancel
            walkCalls.append(.init(
                root: root,
                pattern: pattern,
                maxDepth: maxDepth,
                cap: cap,
                includeHidden: includeHidden
            ))
            let entries = entries
            let holdOpen = holdOpen
            return AsyncThrowingStream { continuation in
                for entry in entries {
                    continuation.yield(entry)
                }
                if holdOpen {
                    Task {
                        while !cancel.isCancelled {
                            try? await Task.sleep(nanoseconds: 10_000_000)
                        }
                        continuation.finish()
                    }
                    return
                }
                continuation.finish()
            }
        }
    }

    private func mkEntry(
        _ name: String,
        kind: FileKind = .Regular,
        size: UInt64 = 0,
        modified: Int64 = 0
    ) -> FileEntry {
        FileEntry(
            path: RustString("/tmp/\(name)"),
            name: RustString(name),
            size: size,
            modified_unix: modified,
            kind: kind,
            is_hidden: false,
            icon_kind: kind == .Directory ? .Folder : .GenericFile
        )
    }

    private func defaultSort() -> FolderModel.SortDescriptor {
        .init(field: .name, order: .ascending)
    }

    func test_idle_by_default() {
        let m = SearchModel(engine: engine())
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(m.results.isEmpty)
        XCTAssertFalse(m.isActive)
    }

    func test_folder_mode_filters_in_memory() {
        let m = SearchModel(engine: engine())
        m.query = "readme"
        m.scope = .folder
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: [
                mkEntry("README.md"),
                mkEntry("main.swift"),
                mkEntry("readme.txt"),
            ]
        )
        let names = m.results.map { $0.name.toString() }
        XCTAssertEqual(Set(names), Set(["README.md", "readme.txt"]))
        XCTAssertEqual(m.phase, .done)
        XCTAssertEqual(m.hitCount, 2)
    }

    func test_empty_query_clears_results() {
        let m = SearchModel(engine: engine())
        m.query = "x"
        m.scope = .folder
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: [mkEntry("xfoo")]
        )
        XCTAssertEqual(m.results.count, 1)

        m.query = ""
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: [mkEntry("xfoo")]
        )
        XCTAssertEqual(m.phase, .idle)
        XCTAssertTrue(m.results.isEmpty)
    }

    func test_folder_mode_preserves_dirs_first_sort() {
        let m = SearchModel(engine: engine())
        m.query = "test"
        m.scope = .folder
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: [
                mkEntry("test.txt", kind: .Regular),
                mkEntry("tests", kind: .Directory),
                mkEntry("beta_test.md", kind: .Regular),
            ]
        )
        let names = m.results.map { $0.name.toString() }
        // Directory bubbles to top regardless; files in case-insensitive name asc.
        XCTAssertEqual(names, ["tests", "beta_test.md", "test.txt"])
    }

    func test_cancel_clears_task_and_handle() {
        let m = SearchModel(engine: engine())
        m.query = "x"
        m.scope = .subtree
        m.refresh(
            root: localRoot("/tmp"),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )
        // Task is spawned; cancel before it finishes the 200ms debounce.
        m.cancel()
        XCTAssertNil(m.activeHandle)
        XCTAssertEqual(m.phase, .idle)
    }

    func test_scope_toggle_does_not_crash() {
        let m = SearchModel(engine: engine())
        m.query = "x"
        m.scope = .folder
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )
        m.scope = .subtree
        m.refresh(
            root: localRoot(),
            provider: localProvider(),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )
        m.cancel()
    }

    @MainActor
    func test_remote_subtree_routesToProviderWalk() async throws {
        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "remote-search")
        let provider = RecordingWalkProvider(target: target)
        provider.entries = [mkEntry("sshd_config")]
        let m = SearchModel(engine: engine())
        m.query = "conf"
        m.scope = .subtree

        m.refresh(
            root: FSPath(provider: .ssh(target), path: "/etc"),
            provider: provider,
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )

        for _ in 0..<50 where m.phase != .done {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(provider.walkCalls.count, 1)
        XCTAssertEqual(provider.walkCalls.first?.root.path, "/etc")
        XCTAssertEqual(provider.walkCalls.first?.pattern, "conf")
        XCTAssertEqual(provider.walkCalls.first?.maxDepth, 10)
        XCTAssertEqual(provider.walkCalls.first?.cap, 10_000)
        XCTAssertEqual(provider.walkCalls.first?.includeHidden, false)
        XCTAssertEqual(m.results.map { $0.name.toString() }, ["sshd_config"])
        XCTAssertEqual(m.hitCount, 1)
        XCTAssertEqual(m.phase, .done)
    }

    @MainActor
    func test_clear_cancelsInflightRemoteWalk() async throws {
        let target = SshTarget(user: "tester", hostname: "example.com", port: 22, configHashHex: "remote-clear")
        let provider = RecordingWalkProvider(target: target)
        provider.holdOpen = true
        let m = SearchModel(engine: engine())
        m.query = "conf"
        m.scope = .subtree

        m.refresh(
            root: FSPath(provider: .ssh(target), path: "/etc"),
            provider: provider,
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )

        for _ in 0..<50 where provider.lastCancel == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        m.clear()

        XCTAssertTrue(provider.lastCancel?.isCancelled ?? false)
        XCTAssertEqual(m.query, "")
        XCTAssertTrue(m.results.isEmpty)
        XCTAssertEqual(m.hitCount, 0)
        XCTAssertEqual(m.phase, .idle)
    }
}
