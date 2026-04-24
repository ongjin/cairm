import XCTest
@testable import Cairn

@MainActor
final class FolderCompareModelTests: XCTestCase {
    func test_run_populatesResultAndFlipsPhase() async throws {
        let provider = InMemoryProvider(tree: [
            "/L": ["a", "b"],
            "/R": ["a"],
        ])
        let model = FolderCompareModel()

        await model.run(
            leftRoot: FSPath(provider: .local, path: "/L"),
            rightRoot: FSPath(provider: .local, path: "/R"),
            leftProvider: provider, rightProvider: provider,
            mode: .nameSizeMtime, recursive: false
        )

        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result.onlyLeft.map(\.name), ["b"])
    }

    func test_applySync_enqueuesTransfersForSelectedEntries() async {
        let transfers = TransferController()
        let model = FolderCompareModel()
        model.result.onlyLeft = [CompareEntry(name: "a", size: 1, mtime: Date(), isDirectory: false)]

        model.applySync(
            direction: .leftToRight,
            selected: Set(["a"]),
            leftRoot: FSPath(provider: .local, path: "/L"),
            rightRoot: FSPath(provider: .local, path: "/R"),
            transfers: transfers
        )

        XCTAssertEqual(transfers.pendingOrActiveCount, 1)
    }

    func test_retryAfterCancelKeepsLatestResult() async throws {
        let gate = AsyncListGate()
        let slowProvider = GatedProvider(tree: [
            "/L": ["stale"],
            "/R": [],
        ], gate: gate)
        let freshProvider = InMemoryProvider(tree: [
            "/L": ["fresh"],
            "/R": [],
        ])
        let model = FolderCompareModel()
        let leftRoot = FSPath(provider: .local, path: "/L")
        let rightRoot = FSPath(provider: .local, path: "/R")

        let staleScan = Task {
            await model.run(
                leftRoot: leftRoot,
                rightRoot: rightRoot,
                leftProvider: slowProvider,
                rightProvider: slowProvider,
                mode: .nameSizeMtime,
                recursive: true
            )
        }
        await gate.waitUntilStarted()

        model.cancelRunning()

        await model.run(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            leftProvider: freshProvider,
            rightProvider: freshProvider,
            mode: .nameSizeMtime,
            recursive: false
        )
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result.onlyLeft.map(\.name), ["fresh"])

        await gate.release()
        await staleScan.value

        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result.onlyLeft.map(\.name), ["fresh"])
    }
}

actor AsyncListGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func arriveAndWait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

final class GatedProvider: FileSystemProvider {
    let identifier: ProviderID = .local
    let displayScheme: String? = nil
    let supportsServerSideCopy = false

    private let tree: [String: [String]]
    private let gate: AsyncListGate

    init(tree: [String: [String]], gate: AsyncListGate) {
        self.tree = tree
        self.gate = gate
    }

    func list(_ path: FSPath) async throws -> [FileEntry] {
        await gate.arriveAndWait()
        let names = tree[path.path] ?? []
        return names.map { name in
            let childPath = path.appending(name).path
            let isDirectory = tree[childPath] != nil
            return FileEntry(
                path: RustString(childPath),
                name: RustString(name),
                size: isDirectory ? 0 : 1,
                modified_unix: 0,
                kind: isDirectory ? .Directory : .Regular,
                is_hidden: false,
                icon_kind: isDirectory ? .Folder : .GenericFile
            )
        }
    }

    func stat(_ path: FSPath) async throws -> FileStat {
        FileStat(size: 0, mtime: nil, mode: 0, isDirectory: tree[path.path] != nil)
    }

    func exists(_ path: FSPath) async throws -> Bool { tree[path.path] != nil }
    func mkdir(_ path: FSPath) async throws {}
    func rename(from: FSPath, to: FSPath) async throws {}
    func delete(_ paths: [FSPath]) async throws {}
    func copyInPlace(from: FSPath, to: FSPath) async throws {}
    func readHead(_ path: FSPath, max: Int) async throws -> Data { Data() }
    func downloadToCache(_ path: FSPath) async throws -> URL { URL(fileURLWithPath: path.path) }
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {}
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {}
    func realpath(_ path: String) async throws -> String { path }
}
