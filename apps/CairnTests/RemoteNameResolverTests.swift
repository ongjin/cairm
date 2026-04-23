import XCTest
@testable import Cairn

final class RemoteNameResolverTests: XCTestCase {
    private let dir = FSPath(provider: .local, path: "/tmp/fake")

    // MARK: - Happy path (collision avoidance)

    func test_noCollision_returnsBaseName() async throws {
        let existing: Set<String> = []
        let result = try await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled.png")
    }

    func test_oneCollision_appendsTwo() async throws {
        let existing: Set<String> = ["/tmp/fake/Untitled.png"]
        let result = try await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 2.png")
    }

    func test_multipleCollisions_walksUntilFree() async throws {
        let existing: Set<String> = [
            "/tmp/fake/Untitled.png",
            "/tmp/fake/Untitled 2.png",
            "/tmp/fake/Untitled 3.png",
        ]
        let result = try await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "png", in: dir,
            probe: { existing.contains($0.path) }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled 4.png")
    }

    func test_emptyExtension_omitsDot() async throws {
        let result = try await RemoteNameResolver.uniqueRemotePath(
            base: "Untitled", ext: "", in: dir,
            probe: { _ in false }
        )
        XCTAssertEqual(result.path, "/tmp/fake/Untitled")
    }

    // MARK: - Probe error propagation
    //
    // Regression coverage for the follow-up Codex finding: if the probe
    // swallows transport/permission errors as "doesn't exist" the resolver
    // will hand back a path that may already have content on the remote,
    // and uploadFromLocal's truncate wipes it. The resolver must rethrow.

    private struct TransportError: Error, Equatable {}

    func test_probeThrows_onFirstCandidate_propagates() async {
        do {
            _ = try await RemoteNameResolver.uniqueRemotePath(
                base: "Untitled", ext: "png", in: dir,
                probe: { _ in throw TransportError() }
            )
            XCTFail("expected throw")
        } catch is TransportError {
            // expected
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func test_probeThrows_onLaterCandidate_propagates() async {
        // Simulates: base name is known to exist, but the session drops
        // before we can probe "Untitled 2". Resolver must not silently
        // pick "Untitled 2" — the upload could clobber.
        let probe: (FSPath) async throws -> Bool = { candidate in
            if candidate.path == "/tmp/fake/Untitled.png" { return true }
            throw TransportError()
        }
        do {
            _ = try await RemoteNameResolver.uniqueRemotePath(
                base: "Untitled", ext: "png", in: dir, probe: probe
            )
            XCTFail("expected throw on second probe")
        } catch is TransportError {
            // expected
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
