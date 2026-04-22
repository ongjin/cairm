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
}
