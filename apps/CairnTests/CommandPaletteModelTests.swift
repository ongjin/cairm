import XCTest
@testable import Cairn

final class CommandPaletteModelTests: XCTestCase {
    func test_parse_empty_is_fuzzy() {
        XCTAssertEqual(CommandPaletteModel.parse(""), .fuzzy(""))
    }

    func test_parse_plain_is_fuzzy() {
        XCTAssertEqual(CommandPaletteModel.parse("hello"), .fuzzy("hello"))
    }

    func test_parse_gt_is_command() {
        XCTAssertEqual(CommandPaletteModel.parse(">new tab"), .command("new tab"))
    }

    func test_parse_slash_is_content() {
        XCTAssertEqual(CommandPaletteModel.parse("/class Foo"), .content("class Foo"))
    }

    func test_parse_hash_is_git_dirty() {
        XCTAssertEqual(CommandPaletteModel.parse("#foo"), .gitDirty("foo"))
    }

    func test_parse_at_is_symbol() {
        XCTAssertEqual(CommandPaletteModel.parse("@Bar"), .symbol("Bar"))
    }

    // MARK: - fallbackFuzzyHits

    private func mkFile(_ name: String, path: String) -> FileEntry {
        FileEntry(
            path: RustString(path),
            name: RustString(name),
            size: 0,
            modified_unix: 0,
            kind: .Regular,
            is_hidden: false,
            icon_kind: .GenericFile
        )
    }

    func test_fallbackFuzzyHits_filtersFolderEntries_bySubstring() {
        let engine = CairnEngine()
        let folder = FolderModel(engine: engine)
        folder.setEntries([
            mkFile("Readme.md",  path: "/tmp/Readme.md"),
            mkFile("main.swift", path: "/tmp/main.swift"),
            mkFile("notes.txt",  path: "/tmp/notes.txt")
        ])

        let model = CommandPaletteModel()
        model.query = "swif"

        let hits = model.fallbackFuzzyHits(folder: folder)
        XCTAssertEqual(hits.map(\.pathRel), ["main.swift"])
    }

    func test_fallbackFuzzyHits_emptyQuery_returnsEmpty() {
        let engine = CairnEngine()
        let folder = FolderModel(engine: engine)
        folder.setEntries([mkFile("a.txt", path: "/x/a.txt")])

        let model = CommandPaletteModel()
        model.query = ""

        XCTAssertEqual(model.fallbackFuzzyHits(folder: folder), [])
    }
}
