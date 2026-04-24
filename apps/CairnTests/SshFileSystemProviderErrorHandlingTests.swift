import XCTest
@testable import Cairn

final class SshFileSystemProviderErrorHandlingTests: XCTestCase {
    func testTerminalSessionErrorsInvalidateTargetExactlyOnce() async throws {
        let markers = [
            "SFTP: session closed",
            "Connection to example.com lost",
            "Russh: transport closed",
            "SFTP: sftp timeout"
        ]

        for marker in markers {
            let pool = FakeSftpHandleProvider()
            let target = Self.target()
            let provider = SshFileSystemProvider(pool: pool, target: target)

            do {
                let _: Void = try await provider.surfaceForTesting {
                    throw RustString(marker)
                }
                XCTFail("expected \(marker) to be rethrown")
            } catch {
                XCTAssertEqual((error as? RustString)?.toString(), marker)
            }

            XCTAssertEqual(pool.invalidatedTargets, [target])
        }
    }

    func testNonTerminalErrorsDoNotInvalidateTarget() async throws {
        for message in ["Not found: /x", "Permission denied: /x"] {
            let pool = FakeSftpHandleProvider()
            let target = Self.target()
            let provider = SshFileSystemProvider(pool: pool, target: target)

            do {
                let _: Void = try await provider.surfaceForTesting {
                    throw RustString(message)
                }
                XCTFail("expected \(message) to be rethrown")
            } catch {
                XCTAssertEqual((error as? RustString)?.toString(), message)
            }

            XCTAssertTrue(pool.invalidatedTargets.isEmpty)
        }
    }

    private static func target() -> SshTarget {
        SshTarget(
            user: "tester",
            hostname: "example.com",
            port: 22,
            configHashHex: "deadbeef"
        )
    }
}

private final class FakeSftpHandleProvider: SftpHandleProviding {
    private(set) var invalidatedTargets: [SshTarget] = []

    func sftpHandle(for target: SshTarget) async throws -> SftpHandleBridge {
        XCTFail("test should not request a real SFTP handle")
        throw RustString("unexpected handle request")
    }

    func invalidate(_ target: SshTarget) {
        invalidatedTargets.append(target)
    }
}
