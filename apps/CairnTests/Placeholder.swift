import XCTest

final class PlaceholderTests: XCTestCase {
    func test_placeholder_for_future_targets() {
        // Ensures the CairnTests target compiles and xcodebuild test runs.
        XCTAssertEqual(1 + 1, 2)
    }
}
