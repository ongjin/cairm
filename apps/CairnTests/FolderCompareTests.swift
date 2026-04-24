import XCTest
@testable import Cairn

final class FolderCompareTests: XCTestCase {
    func test_result_isEmpty_whenBothSidesIdentical() {
        let left = [entry(name: "a", size: 10, mtime: 100)]
        let right = [entry(name: "a", size: 10, mtime: 100)]
        let result = FolderCompare.compare(left: left, right: right, mode: .nameSizeMtime)
        XCTAssertTrue(result.onlyLeft.isEmpty)
        XCTAssertTrue(result.onlyRight.isEmpty)
        XCTAssertTrue(result.changed.isEmpty)
        XCTAssertEqual(result.same.map(\.name), ["a"])
    }

    func test_onlyLeft_whenNameMissingOnRight() {
        let result = FolderCompare.compare(
            left: [entry(name: "a", size: 1, mtime: 0), entry(name: "b", size: 1, mtime: 0)],
            right: [entry(name: "a", size: 1, mtime: 0)],
            mode: .nameSizeMtime
        )
        XCTAssertEqual(result.onlyLeft.map(\.name), ["b"])
        XCTAssertTrue(result.onlyRight.isEmpty)
    }

    func test_onlyRight_whenNameMissingOnLeft() {
        let result = FolderCompare.compare(
            left: [entry(name: "a", size: 1, mtime: 0)],
            right: [entry(name: "a", size: 1, mtime: 0), entry(name: "b", size: 1, mtime: 0)],
            mode: .nameSizeMtime
        )
        XCTAssertEqual(result.onlyRight.map(\.name), ["b"])
    }

    func test_changed_whenSizeDiffers() {
        let result = FolderCompare.compare(
            left: [entry(name: "a", size: 1, mtime: 0)],
            right: [entry(name: "a", size: 2, mtime: 0)],
            mode: .nameSizeMtime
        )
        XCTAssertEqual(result.changed.map(\.name), ["a"])
    }

    func test_changed_whenMtimeDiffersBeyondTolerance() {
        let result = FolderCompare.compare(
            left: [entry(name: "a", size: 1, mtime: 0)],
            right: [entry(name: "a", size: 1, mtime: 5)],
            mode: .nameSizeMtime
        )
        XCTAssertEqual(result.changed.map(\.name), ["a"])
    }

    func test_nameOnlyMode_treatsAllMatchesAsSame() {
        let result = FolderCompare.compare(
            left: [entry(name: "a", size: 1, mtime: 0)],
            right: [entry(name: "a", size: 999, mtime: 999)],
            mode: .nameOnly
        )
        XCTAssertEqual(result.same.map(\.name), ["a"])
        XCTAssertTrue(result.changed.isEmpty)
    }

    func test_recursiveCompare_walksSubdirectoriesAndReportsRelativePaths() async throws {
        let left = InMemoryProvider(tree: [
            "/root": ["foo"],
            "/root/foo": ["a", "b"],
        ])
        let right = InMemoryProvider(tree: [
            "/root": ["foo"],
            "/root/foo": ["a"],
        ])

        let result = try await FolderCompare.compareRecursive(
            leftRoot: "/root", leftProvider: left,
            rightRoot: "/root", rightProvider: right,
            mode: .nameSizeMtime,
            cancel: CancelToken()
        )

        XCTAssertEqual(result.onlyLeft.map(\.name), ["foo/b"])
    }

    private func entry(name: String, size: Int64, mtime: TimeInterval) -> CompareEntry {
        CompareEntry(name: name, size: size, mtime: Date(timeIntervalSince1970: mtime), isDirectory: false)
    }
}

private final class InMemoryProvider: FileSystemProvider {
    let identifier: ProviderID = .local
    let displayScheme: String? = nil
    let supportsServerSideCopy = false

    private let tree: [String: [String]]

    init(tree: [String: [String]]) {
        self.tree = tree
    }

    func list(_ path: FSPath) async throws -> [FileEntry] {
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
