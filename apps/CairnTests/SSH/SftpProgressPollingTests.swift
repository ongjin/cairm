import XCTest
@testable import Cairn

@MainActor
final class SftpProgressPollingTests: XCTestCase {
    func test_pollingFiresSinkWhileWorkRuns() async throws {
        nonisolated(unsafe) var counter: Int64 = 0
        nonisolated(unsafe) var observed: [Int64] = []

        try await runWithProgressPolling(
            interval: .milliseconds(30),
            poll: { counter },
            sink: { observed.append($0) },
            work: {
                for i in 1...5 {
                    try await Task.sleep(for: .milliseconds(40))
                    counter = Int64(i) * 100
                }
            }
        )

        XCTAssertGreaterThanOrEqual(observed.count, 5)
        XCTAssertEqual(observed.last, 500)
    }

    func test_workErrorPropagates() async throws {
        struct BoomError: Error {}

        do {
            try await runWithProgressPolling(
                interval: .milliseconds(30),
                poll: { 0 },
                sink: { _ in },
                work: { throw BoomError() }
            )
            XCTFail("expected throw")
        } catch is BoomError {
            // expected
        }
    }
}
