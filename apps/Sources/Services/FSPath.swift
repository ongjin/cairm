import Foundation

/// Uniquely identifies a FileSystemProvider instance. Used as a hashable
/// key across Tab/FolderModel/TransferJob so two tabs on the same SSH host
/// route to the same provider instance.
enum ProviderID: Hashable, Codable {
    case local
    case ssh(SshTarget)
}

struct SshTarget: Hashable, Codable {
    let user: String
    let hostname: String
    let port: UInt16
    let configHashHex: String        // mirrors Rust ConnKey.config_hash
}

/// Abstract path on a provider. `path` is POSIX-style absolute for both
/// local ("/Users/cyj/...") and SSH ("/var/log/nginx").
struct FSPath: Hashable, Codable {
    let provider: ProviderID
    let path: String

    var lastComponent: String {
        (path as NSString).lastPathComponent
    }

    func appending(_ component: String) -> FSPath {
        let base = path.hasSuffix("/") ? path : path + "/"
        return FSPath(provider: provider, path: base + component)
    }

    func parent() -> FSPath? {
        if path == "/" || path.isEmpty { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        return FSPath(provider: provider, path: parent.isEmpty ? "/" : parent)
    }

    var isLocal: Bool { if case .local = provider { return true } else { return false } }
}
