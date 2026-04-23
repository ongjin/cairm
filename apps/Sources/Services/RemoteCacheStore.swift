import Foundation
import CryptoKit

final class RemoteCacheStore {
    static let shared = RemoteCacheStore()

    private let root: URL
    private let limitBytes: Int64 = 500 * 1024 * 1024
    private let lock = NSLock()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Cairn/remote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.root = dir
    }

    func cacheURL(for path: FSPath) -> URL {
        guard case .ssh(let t) = path.provider else {
            return URL(fileURLWithPath: path.path)
        }
        let hostKey = "\(t.user)@\(t.hostname)-\(t.port)"
        var h = SHA256()
        h.update(data: Data(path.path.utf8))
        let hash = h.finalize().map { String(format: "%02x", $0) }.joined()
        let ext = (path.path as NSString).pathExtension
        let filename = ext.isEmpty ? hash : "\(hash).\(ext)"
        return root.appendingPathComponent(hostKey).appendingPathComponent(filename)
    }

    func fetch(remotePath: FSPath, via provider: FileSystemProvider) async throws -> URL {
        let url = cacheURL(for: remotePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let remoteStat = try await provider.stat(remotePath)
        if FileManager.default.fileExists(atPath: url.path) {
            let localAttr = try? FileManager.default.attributesOfItem(atPath: url.path)
            let localMtime = (localAttr?[.modificationDate] as? Date) ?? .distantPast
            if let rm = remoteStat.mtime, rm <= localMtime {
                return url
            }
        }
        let cancel = CancelToken()
        try await provider.downloadToLocal(remotePath, toLocalURL: url, progress: { _ in }, cancel: cancel)
        if let rm = remoteStat.mtime {
            try? FileManager.default.setAttributes([.modificationDate: rm], ofItemAtPath: url.path)
        }
        enforceLimit()
        return url
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func enforceLimit() {
        lock.lock(); defer { lock.unlock() }
        var all: [(URL, Int64, Date)] = []
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var total: Int64 = 0
        for case let u as URL in walker {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
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
