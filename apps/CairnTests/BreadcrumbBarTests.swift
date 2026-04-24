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

    // MARK: - SSH segment abbreviation

    func test_sshSegments_insideUserHome_collapsesToTilde() {
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/home/ubuntu/infra/nginx", user: "ubuntu"),
            ["~", "infra", "nginx"]
        )
    }

    func test_sshSegments_atUserHomeExactly_returnsTildeOnly() {
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/home/ubuntu", user: "ubuntu"),
            ["~"]
        )
    }

    func test_sshSegments_insideRootHome_collapsesToTilde() {
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/root/scripts", user: "root"),
            ["~", "scripts"]
        )
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/root", user: "root"),
            ["~"]
        )
    }

    func test_sshSegments_outsideHome_leavesPathIntact() {
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/opt/app/conf", user: "ubuntu"),
            ["opt", "app", "conf"]
        )
        // Don't collapse another user's home.
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/home/alice/data", user: "ubuntu"),
            ["home", "alice", "data"]
        )
    }

    func test_sshSegments_rootPath_returnsEmpty() {
        XCTAssertEqual(
            BreadcrumbBar.sshSegments(path: "/", user: "ubuntu"),
            []
        )
    }
}
