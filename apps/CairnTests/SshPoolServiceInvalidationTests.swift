import XCTest
@testable import Cairn

final class SshPoolServiceInvalidationTests: XCTestCase {
    func testInvalidateDropsCachedHandleAndMarksSessionError() {
        let pool = SshPoolService.forTesting()
        let target = SshTarget(
            user: "tester",
            hostname: "example.com",
            port: 22,
            configHashHex: "deadbeef"
        )
        let handle = SftpHandleBridge(ptr: UnsafeMutableRawPointer(bitPattern: 0x1)!)
        handle.isOwned = false

        pool.seedCachedSftpHandleForTesting(handle, for: target)
        XCTAssertTrue(pool.hasCachedSftpHandleForTesting(for: target))

        pool.invalidate(target)

        XCTAssertFalse(pool.hasCachedSftpHandleForTesting(for: target))
        guard case .error(let message)? = pool.sessions[target]?.status else {
            return XCTFail("expected invalidated session to be marked as error")
        }
        XCTAssertEqual(message, "session dropped")
    }
}
