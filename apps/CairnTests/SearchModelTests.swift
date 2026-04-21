import XCTest
@testable import Cairn

final class SearchModelTests: XCTestCase {
    private func engine() -> CairnEngine { CairnEngine() }

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
            root: URL(fileURLWithPath: "/"),
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
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: [mkEntry("xfoo")]
        )
        XCTAssertEqual(m.results.count, 1)

        m.query = ""
        m.refresh(
            root: URL(fileURLWithPath: "/"),
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
        m.refresh(
            root: URL(fileURLWithPath: "/"),
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
            root: URL(fileURLWithPath: "/tmp"),
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
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )
        m.scope = .subtree
        m.refresh(
            root: URL(fileURLWithPath: "/"),
            showHidden: false,
            sort: defaultSort(),
            folderEntries: []
        )
        m.cancel()
    }
}
