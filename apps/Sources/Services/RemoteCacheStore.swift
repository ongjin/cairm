import Foundation
import CryptoKit

actor RemoteCacheStore {
    static let shared = RemoteCacheStore()

    private let root: URL
    private let limitBytes: Int64 = 500 * 1024 * 1024
    /// Each in-flight entry keeps both the wrapping Task and the cancel
    /// token that drives `downloadToLocal`. `clear()` needs both: it
    /// flips the token so the SFTP copy tears down promptly, then
    /// awaits the task so the cache-root recreate races nothing.
    private struct InflightEntry {
        let task: Task<URL, any Error>
        let cancel: CancelToken
    }
    private var inflight: [URL: InflightEntry] = [:]

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
            return try await existing.task.value
        }
        let cancel = CancelToken()
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
            // Download into a sibling temp path and atomically replace
            // the final URL only on success. Writing directly to `url`
            // would leave partial bytes under the canonical name on
            // cancel/timeout, and the next fetch's mtime freshness
            // check would happily hand that truncated file to Quick
            // Look / Open With.
            let tempURL = url
                .deletingLastPathComponent()
                .appendingPathComponent(".partial-\(UUID().uuidString)")
            do {
                try await provider.downloadToLocal(remotePath, toLocalURL: tempURL,
                                                   progress: { _ in }, cancel: cancel)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            if cancel.isCancelled {
                try? FileManager.default.removeItem(at: tempURL)
                throw CancellationError()
            }
            // Replace existing final file if any, then move temp into place.
            try? FileManager.default.removeItem(at: url)
            do {
                try FileManager.default.moveItem(at: tempURL, to: url)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            if let rm = remoteStat.mtime {
                try? FileManager.default.setAttributes([.modificationDate: rm],
                                                       ofItemAtPath: url.path)
            }
            return url
        }
        inflight[url] = InflightEntry(task: t, cancel: cancel)
        defer { inflight.removeValue(forKey: url) }
        let result = try await t.value
        enforceLimit()
        return result
    }

    func clear() async {
        // Flip every in-flight cancel token so the underlying SFTP
        // transfers stop writing to disk, then await each task so the
        // cache root recreate below races nothing. Without this, a
        // cancelled download could finish writing its temp file AFTER
        // we remove `root`, repopulating a supposedly-cleared cache
        // from the wrong environment.
        let entries = Array(inflight.values)
        for entry in entries { entry.cancel.cancel() }
        inflight.removeAll()
        for entry in entries {
            _ = try? await entry.task.value
        }
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
