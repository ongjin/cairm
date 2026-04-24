import XCTest
@testable import Cairn

@MainActor
final class FolderCompareModelTests: XCTestCase {
    func test_run_populatesResultAndFlipsPhase() async throws {
        let provider = InMemoryProvider(tree: [
            "/L": ["a", "b"],
            "/R": ["a"],
        ])
        let model = FolderCompareModel()

        await model.run(
            leftRoot: FSPath(provider: .local, path: "/L"),
            rightRoot: FSPath(provider: .local, path: "/R"),
            leftProvider: provider, rightProvider: provider,
            mode: .nameSizeMtime, recursive: false
        )

        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.result.onlyLeft.map(\.name), ["b"])
    }
}
