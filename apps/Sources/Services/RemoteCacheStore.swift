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
    /// Barrier task set while a `clear()` is running. New `fetch()`
    /// calls `await` this before starting new work so the post-clear
    /// `removeItem(root)` can't race with a fresh download writing
    /// into the same directory. Actor reentrancy would otherwise let
    /// a fetch sneak in between `clear()`'s cancel+await and its
    /// remove/recreate step.
    private var clearBarrier: Task<Void, Never>?

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
        // Await any in-flight clear before starting new work. The
        // while loop re-checks after every await because actor
        // reentrancy lets another clear set the barrier while we
        // were suspended.
        while let barrier = clearBarrier {
            await barrier.value
        }
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
        // Coalesce concurrent clears: callers joining while another
        // clear is running simply wait for it and return.
        if let existing = clearBarrier {
            await existing.value
            return
        }
        // Snapshot in-flight entries under actor isolation before
        // entering the async barrier task. Flipping the cancel tokens
        // stops the underlying SFTP transfers from writing to disk.
        let entries = Array(inflight.values)
        for entry in entries { entry.cancel.cancel() }
        inflight.removeAll()
        // The barrier task awaits cancelled downloads, then removes
        // and recreates the cache root. We hold `clearBarrier` from
        // BEFORE the await so any fetch that enters mid-clear sees
        // the barrier and parks in its while-loop. `root` is captured
        // by value (URL is Sendable) so the detached task doesn't
        // reach back into actor-isolated state.
        let rootLocal = root
        let task = Task<Void, Never>.detached {
            for entry in entries {
                _ = try? await entry.task.value
            }
            try? FileManager.default.removeItem(at: rootLocal)
            try? FileManager.default.createDirectory(at: rootLocal, withIntermediateDirectories: true)
        }
        clearBarrier = task
        await task.value
        clearBarrier = nil
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
