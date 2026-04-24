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

    private func entry(name: String, size: Int64, mtime: TimeInterval) -> CompareEntry {
        CompareEntry(name: name, size: size, mtime: Date(timeIntervalSince1970: mtime), isDirectory: false)
    }
}
