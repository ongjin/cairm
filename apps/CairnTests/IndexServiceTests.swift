import XCTest
@testable import Cairn

final class IndexServiceTests: XCTestCase {
    private func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func test_open_returns_service() {
        let d = tmpDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try! "hi".write(to: d.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let svc = IndexService(root: d)
        XCTAssertNotNil(svc)
    }

    func test_query_fuzzy_returns_hits() {
        let d = tmpDir()
        defer { try? FileManager.default.removeItem(at: d) }
        try! "x".write(to: d.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        try! "y".write(to: d.appendingPathComponent("world.txt"), atomically: true, encoding: .utf8)
        let svc = IndexService(root: d)!
        let hits = svc.queryFuzzy("hell", limit: 10)
        XCTAssertTrue(hits.contains { $0.pathRel == "hello.txt" })
    }
}
