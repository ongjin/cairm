import Foundation
import CryptoKit

actor RemoteCacheStore {
    static let shared = RemoteCacheStore()

    private let root: URL
    private let limitBytes: Int64 = 500 * 1024 * 1024
    private var inflight: [URL: Task<URL, any Error>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Cairn/remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.root = dir
    }

    nonisolated func cacheURL(for path: FSPath) -> URL {
        guard case .ssh(let t) = path.provider else {
            return URL(fileURLWithPath: path.path)
        }
        // Include `configHashHex` in the host key so two ssh_config
        // aliases that share user/host/port but point at different
        // environments (different ProxyCommand, IdentityFile, etc.)
        // don't alias onto the same cached file. The `inflight`
        // dedup map is keyed off this URL, so alias collisions
        // would otherwise hand Quick Look / Open With a file
        // downloaded from the wrong host environment.
        let hostKey = "\(t.user)@\(t.hostname)-\(t.port)-\(t.configHashHex)"
        var h = SHA256()
        h.update(data: Data(path.path.utf8))
        let hash = h.finalize().map { String(format: "%02x", $0) }.joined()
        let ext = (path.path as NSString).pathExtension
        let filename = ext.isEmpty ? hash : "\(hash).\(ext)"
        return root.appendingPathComponent(hostKey).appendingPathComponent(filename)
    }

    func fetch(remotePath: FSPath, via provider: FileSystemProvider) async throws -> URL {
        let url = cacheURL(for: remotePath)
        // Deduplicate concurrent downloads for the same cache URL
        if let existing = inflight[url] {
            return try await existing.value
        }
        let t = Task<URL, any Error> { [url] in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let remoteStat = try await provider.stat(remotePath)
            if FileManager.default.fileExists(atPath: url.path) {
                let localAttr = try? FileManager.default.attributesOfItem(atPath: url.path)
                let localMtime = (localAttr?[.modificationDate] as? Date) ?? .distantPast
                if let rm = remoteStat.mtime, rm <= localMtime {
                    return url
                }
            }
            let cancel = CancelToken()
            try await provider.downloadToLocal(remotePath, toLocalURL: url,
                                               progress: { _ in }, cancel: cancel)
            if let rm = remoteStat.mtime {
                try? FileManager.default.setAttributes([.modificationDate: rm],
                                                       ofItemAtPath: url.path)
            }
            return url
        }
        inflight[url] = t
        defer { inflight.removeValue(forKey: url) }
        let result = try await t.value
        enforceLimit()
        return result
    }

    func clear() {
        // Cancel all in-flight downloads first
        for (_, task) in inflight { task.cancel() }
        inflight.removeAll()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func enforceLimit() {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        ) else { return }
        var all: [(URL, Int64, Date)] = []
        var total: Int64 = 0
        for case let u as URL in walker {
            let v = try? u.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard v?.isRegularFile == true else { continue }
            let size = Int64(v?.fileSize ?? 0)
            let mtime = v?.contentModificationDate ?? .distantPast
            all.append((u, size, mtime))
            total += size
        }
        guard total > limitBytes else { return }
        all.sort { $0.2 < $1.2 }
        for (u, size, _) in all {
            if total <= limitBytes { break }
            try? FileManager.default.removeItem(at: u)
            total -= size
        }
    }
}
