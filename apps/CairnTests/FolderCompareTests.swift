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

    private func entry(name: String, size: Int64, mtime: TimeInterval) -> CompareEntry {
        CompareEntry(name: name, size: size, mtime: Date(timeIntervalSince1970: mtime), isDirectory: false)
    }
}
