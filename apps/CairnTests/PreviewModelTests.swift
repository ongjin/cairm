import XCTest
@testable import Cairn

@MainActor
final class PreviewModelTests: XCTestCase {
    func test_initial_state_is_idle() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        if case .idle = model.state {} else { XCTFail("initial state should be .idle") }
        XCTAssertNil(model.focus)
    }

    func test_focus_nil_clears_state_to_idle() async {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Preload a focused URL → directory case.
        model.focus = FileManager.default.temporaryDirectory
        model.state = .directory(childCount: 5)
        model.focus = nil
        if case .idle = model.state {} else { XCTFail("nil focus should reset to .idle") }
    }

    func test_lru_caches_up_to_16_then_evicts_oldest() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Inject 17 arbitrary cached URLs — the first one should be evicted.
        for i in 0..<17 {
            let u = URL(fileURLWithPath: "/tmp/preview-\(i)")
            model.cache(state: .text("content-\(i)"), for: u)
        }
        XCTAssertNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-0")),
                     "oldest entry should have been evicted")
        XCTAssertNotNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-16")),
                        "newest entry should be present")
    }

    // Regression: a prior iteration short-circuited PreviewPaneView on
    // any remote focus, hiding the fetched head-preview states. This
    // verifies the model still transitions to `.text` when readHead
    // returns plausibly-textual bytes, so the view can render it.
    func test_setRemoteFocus_transitions_to_text_state() async {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        let provider = HeadStubProvider(head: Data("hello, world".utf8))
        let path = FSPath(provider: .local, path: "/remote/foo.txt")
        model.setRemoteFocus(path, via: provider)
        // Debounce is 120ms inside PreviewModel — wait past it plus a
        // margin so the loadHead task has applied the result.
        try? await Task.sleep(nanoseconds: 300_000_000)
        if case .text(let s) = model.state {
            XCTAssertEqual(s, "hello, world")
        } else {
            XCTFail("expected .text state after remote head fetch, got \(model.state)")
        }
    }

    func test_setRemoteFocus_binary_head_transitions_to_pressSpaceForFullPreview() async {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Embed a NUL byte — isLikelyText treats that as non-text.
        let provider = HeadStubProvider(head: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]))
        let path = FSPath(provider: .local, path: "/remote/bin.dat")
        model.setRemoteFocus(path, via: provider)
        try? await Task.sleep(nanoseconds: 300_000_000)
        if case .pressSpaceForFullPreview = model.state {
            // expected
        } else {
            XCTFail("expected .pressSpaceForFullPreview, got \(model.state)")
        }
    }

    // Regression: PreviewModel used to key the LRU purely by URL path, so
    // a same-path selection across local / host-A / host-B would hit the
    // same cache slot and restore the wrong content after an inspector
    // toggle. The provider-aware key must keep them distinct.

    private func sshTarget(host: String) -> SshTarget {
        SshTarget(user: "alice", hostname: host, port: 22, configHashHex: "deadbeef")
    }

    func test_cache_localAndRemote_sameBarePath_doNotAlias() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        let url = URL(fileURLWithPath: "/etc/hosts")
        let remote = FSPath(provider: .ssh(sshTarget(host: "server-a")), path: "/etc/hosts")

        model.cache(state: .text("local body"), for: url, remote: nil)
        model.cache(state: .text("remote body"), for: url, remote: remote)

        if case .text(let localHit) = model.cached(for: url, remote: nil) {
            XCTAssertEqual(localHit, "local body")
        } else {
            XCTFail("local cache miss")
        }
        if case .text(let remoteHit) = model.cached(for: url, remote: remote) {
            XCTAssertEqual(remoteHit, "remote body")
        } else {
            XCTFail("remote cache miss")
        }
    }

    // Regression: selecting a remote directory used to route through
    // setRemoteFocus → readHead, which fails on SFTP because opening
    // a directory as a file is a protocol error. That turned
    // "scroll through a remote folder" into false `.failed` pane
    // states once the inspector was re-enabled. setRemoteDirectoryFocus
    // short-circuits to a `.directory(nil)` state without any async
    // I/O — the state must flip synchronously and readHead must not
    // be called (TrappingHeadStubProvider fatalError-s if it is).
    func test_setRemoteDirectoryFocus_setsDirectoryState_withoutReadHead() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        let path = FSPath(provider: .ssh(sshTarget(host: "server-a")), path: "/var/log")
        model.setRemoteDirectoryFocus(path)
        if case .directory(let count) = model.state {
            XCTAssertNil(count, "remote directory preview should not claim a child count")
        } else {
            XCTFail("expected .directory state, got \(model.state)")
        }
    }

    func test_cache_twoSshHosts_sameBarePath_doNotAlias() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        let url = URL(fileURLWithPath: "/etc/hosts")
        let remoteA = FSPath(provider: .ssh(sshTarget(host: "server-a")), path: "/etc/hosts")
        let remoteB = FSPath(provider: .ssh(sshTarget(host: "server-b")), path: "/etc/hosts")

        model.cache(state: .text("A body"), for: url, remote: remoteA)
        model.cache(state: .text("B body"), for: url, remote: remoteB)

        if case .text(let a) = model.cached(for: url, remote: remoteA) {
            XCTAssertEqual(a, "A body")
        } else {
            XCTFail("server-a cache miss")
        }
        if case .text(let b) = model.cached(for: url, remote: remoteB) {
            XCTAssertEqual(b, "B body")
        } else {
            XCTFail("server-b cache miss")
        }
    }
}

/// Minimal FileSystemProvider stub — only `readHead` is wired up because
/// that's the only call path PreviewModel.setRemoteFocus exercises. Any
/// other method traps so tests fail loudly if the code under test
/// starts depending on something new.
private final class HeadStubProvider: FileSystemProvider {
    let identifier: ProviderID = .local
    let displayScheme: String? = nil
    let supportsServerSideCopy: Bool = false

    private let head: Data
    init(head: Data) { self.head = head }

    func readHead(_ path: FSPath, max: Int) async throws -> Data {
        head.prefix(max)
    }

    func list(_ path: FSPath) async throws -> [FileEntry] { fatalError("not used") }
    func stat(_ path: FSPath) async throws -> FileStat { fatalError("not used") }
    func exists(_ path: FSPath) async throws -> Bool { fatalError("not used") }
    func mkdir(_ path: FSPath) async throws { fatalError("not used") }
    func rename(from: FSPath, to: FSPath) async throws { fatalError("not used") }
    func delete(_ paths: [FSPath]) async throws { fatalError("not used") }
    func copyInPlace(from: FSPath, to: FSPath) async throws { fatalError("not used") }
    func downloadToCache(_ path: FSPath) async throws -> URL { fatalError("not used") }
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: (Int64) -> Void, cancel: CancelToken) async throws { fatalError("not used") }
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: (Int64) -> Void, cancel: CancelToken) async throws { fatalError("not used") }
    func realpath(_ path: String) async throws -> String { fatalError("not used") }
}
