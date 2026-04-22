import XCTest
@testable import Cairn

final class BreadcrumbBarTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func test_segments_insideHome_collapsesToTilde() {
        let url = home.appendingPathComponent("Documents/Projects")
        let segs = BreadcrumbBar.segments(for: url, home: home)
        XCTAssertEqual(segs.map(\.label), ["~", "Documents", "Projects"])
        XCTAssertEqual(segs.first?.url, home)
    }

    func test_segments_atHomeRoot_showsOnlyTilde() {
        let segs = BreadcrumbBar.segments(for: home, home: home)
        XCTAssertEqual(segs.map(\.label), ["~"])
        XCTAssertEqual(segs.last?.url, home)
    }

    func test_segments_outsideHome_showsComputerRoot() {
        let url = URL(fileURLWithPath: "/Applications/Utilities")
        let segs = BreadcrumbBar.segments(for: url, home: home)
        XCTAssertEqual(segs.first?.label, BreadcrumbBar.computerName)
        XCTAssertEqual(segs.map(\.label).suffix(2), ["Applications", "Utilities"])
    }
}
