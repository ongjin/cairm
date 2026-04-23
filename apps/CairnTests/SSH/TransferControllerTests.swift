import XCTest
@testable import Cairn

@MainActor
final class TransferControllerTests: XCTestCase {
    func testSerialPerHost() async throws {
        let controller = TransferController()
        let local = FSPath(provider: .local, path: "/tmp/src")
        let target = SshTarget(user: "u", hostname: "h", port: 22,
                               configHashHex: String(repeating: "0", count: 32))
        let remote = FSPath(provider: .ssh(target), path: "/tmp/dst")

        let counter = SerialCounter()

        for i in 0..<3 {
            controller.enqueue(source: local, destination: remote, sizeHint: 10) { _, _ in
                await counter.record(i)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        try await Task.sleep(nanoseconds: 400_000_000)

        let startOrder = await counter.all()
        XCTAssertEqual(startOrder.count, 3)
        XCTAssertEqual(startOrder, [0, 1, 2])
    }

    func testCancelQueued() async throws {
        let controller = TransferController()
        let p = FSPath(provider: .local, path: "/x")
        // First job occupies the local lane
        controller.enqueue(source: p, destination: p, sizeHint: nil) { _, _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        // Second job queues behind it
        controller.enqueue(source: p, destination: p, sizeHint: nil) { _, _ in }
        try await Task.sleep(nanoseconds: 10_000_000) // let first job start
        let id = controller.jobs.last!.id
        controller.cancel(id)
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(controller.jobs.last?.state, .cancelled)
    }
}

private actor SerialCounter {
    private var order: [Int] = []
    func record(_ i: Int) { order.append(i) }
    func all() -> [Int] { order }
}
