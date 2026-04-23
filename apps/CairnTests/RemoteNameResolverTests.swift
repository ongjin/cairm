import XCTest
@testable import Cairn

final class RemoteNameResolverTests: XCTestCase {
    private let dir = FSPath(provider: .local, path: "/tmp/fake")

    func test_noCollision_returnsBaseName() async {
        let existing: Set<String> = []
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled.png")
    }

    func test_oneCollision_appendsTwo() async {
        let existing: Set<String> = ["/tmp/fake/Untitled.png"]
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 2.png")
    }

    func test_multipleCollisions_walksUntilFree() async {
        let existing: Set<String> = [
            "/tmp/fake/Untitled.png",
            "/tmp/fake/Untitled 2.png",
            "/tmp/fake/Untitled 3.png",
        ]
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 4.png")
    }

    func test_emptyExtension_omitsDot() async {
        let result = await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "", in: dir,
            probe: { _ in false }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled")
    }
}
