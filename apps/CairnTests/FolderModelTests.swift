import XCTest
@testable import Cairn

final class FolderModelTests: XCTestCase {
    /// FolderModel 단독 테스트는 CairnEngine 을 호출하지 않는 setEntries 헬퍼를 통해
    /// 직접 entries 를 주입한다. 실제 listDirectory 는 통합 테스트 (수동 E2E) 에서 검증.
    var model: FolderModel!

    override func setUpWithError() throws {
        // CairnEngine() 는 Rust new_engine() 만 호출하므로 사이드이펙트 없음.
        model = FolderModel(engine: CairnEngine())
    }

    private func mkEntry(_ name: String, size: UInt64, modified: Int64, kind: FileKind) -> FileEntry {
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

    func test_sortedEntries_default_is_dirs_first_name_asc() {
        let a = mkEntry("alpha.txt", size: 10, modified: 100, kind: .Regular)
        let z = mkEntry("zeta.txt",  size: 30, modified: 300, kind: .Regular)
        let dir = mkEntry("subdir",  size: 0,  modified: 200, kind: .Directory)
        model.setEntries([z, a, dir])

        let names = model.sortedEntries.map { $0.name.toString() }
        XCTAssertEqual(names, ["subdir", "alpha.txt", "zeta.txt"])
    }

    func test_sortedEntries_by_size_desc_keeps_dirs_first() {
        let a = mkEntry("a.txt", size: 100, modified: 100, kind: .Regular)
        let b = mkEntry("b.txt", size: 500, modified: 200, kind: .Regular)
        let dir = mkEntry("z_dir", size: 0, modified: 50, kind: .Directory)
        model.setEntries([a, b, dir])

        model.setSortDescriptor(.init(field: .size, order: .descending))
        let names = model.sortedEntries.map { $0.name.toString() }
        // 디렉토리 먼저, 그 다음 size 큰 순.
        XCTAssertEqual(names, ["z_dir", "b.txt", "a.txt"])
    }

    func test_sortedEntries_by_modified_asc() {
        let old = mkEntry("old.txt", size: 10, modified: 100, kind: .Regular)
        let new = mkEntry("new.txt", size: 10, modified: 999, kind: .Regular)
        let mid = mkEntry("mid.txt", size: 10, modified: 500, kind: .Regular)
        model.setEntries([new, mid, old])

        model.setSortDescriptor(.init(field: .modified, order: .ascending))
        let names = model.sortedEntries.map { $0.name.toString() }
        XCTAssertEqual(names, ["old.txt", "mid.txt", "new.txt"])
    }

    func test_setSelection_overwrites_previous() {
        let a = mkEntry("a", size: 1, modified: 1, kind: .Regular)
        let b = mkEntry("b", size: 1, modified: 1, kind: .Regular)
        model.setEntries([a, b])

        model.setSelection(["/tmp/a"])
        XCTAssertEqual(model.selection, ["/tmp/a"])
        model.setSelection(["/tmp/b"])
        XCTAssertEqual(model.selection, ["/tmp/b"])
    }

    func test_clear_resets_state_and_selection() {
        let a = mkEntry("a", size: 1, modified: 1, kind: .Regular)
        model.setEntries([a])
        model.setSelection(["/tmp/a"])
        model.clear()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        if case .idle = model.state {} else { XCTFail("state should be .idle after clear()") }
    }
}
