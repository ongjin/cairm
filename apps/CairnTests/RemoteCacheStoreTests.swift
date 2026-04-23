import XCTest
@testable import Cairn

final class RemoteCacheStoreTests: XCTestCase {
    // Regression: cacheURL used to key by `user@host-port` only, so two
    // ssh_config aliases that resolve to the same user/host/port but
    // have different ProxyCommand / IdentityFile / etc. (and therefore
    // different `configHashHex`) would alias onto the same cached file.
    // The user could then Quick Look or Open With a file downloaded
    // from the wrong environment.
    func test_cacheURL_distinctConfigHashes_doNotAlias() {
        let store = RemoteCacheStore()
        let targetA = SshTarget(user: "alice", hostname: "bastion", port: 22, configHashHex: "aaaa")
        let targetB = SshTarget(user: "alice", hostname: "bastion", port: 22, configHashHex: "bbbb")
        let pathA = FSPath(provider: .ssh(targetA), path: "/etc/hosts")
        let pathB = FSPath(provider: .ssh(targetB), path: "/etc/hosts")
        XCTAssertNotEqual(store.cacheURL(for: pathA).path,
                          store.cacheURL(for: pathB).path,
                          "ssh aliases with same user/host/port but different configHashHex must not share cache file")
    }

    func test_cacheURL_sameTarget_samePath_returnsEqualURL() {
        let store = RemoteCacheStore()
        let target = SshTarget(user: "alice", hostname: "bastion", port: 22, configHashHex: "aaaa")
        let path = FSPath(provider: .ssh(target), path: "/etc/hosts")
        XCTAssertEqual(store.cacheURL(for: path).path, store.cacheURL(for: path).path)
    }

    func test_cacheURL_differentHosts_doNotAlias() {
        let store = RemoteCacheStore()
        let targetA = SshTarget(user: "alice", hostname: "host-a", port: 22, configHashHex: "aaaa")
        let targetB = SshTarget(user: "alice", hostname: "host-b", port: 22, configHashHex: "aaaa")
        let pathA = FSPath(provider: .ssh(targetA), path: "/etc/hosts")
        let pathB = FSPath(provider: .ssh(targetB), path: "/etc/hosts")
        XCTAssertNotEqual(store.cacheURL(for: pathA).path, store.cacheURL(for: pathB).path)
    }
}
