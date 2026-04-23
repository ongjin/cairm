import Foundation

struct FileStat {
    let size: Int64
    let mtime: Date?
    let mode: UInt32
    let isDirectory: Bool
}

protocol FileSystemProvider: AnyObject {
    var identifier: ProviderID { get }
    var displayScheme: String? { get }         // nil for local
    var supportsServerSideCopy: Bool { get }

    func list(_ path: FSPath) async throws -> [FileEntry]
    func stat(_ path: FSPath) async throws -> FileStat
    func mkdir(_ path: FSPath) async throws
    func rename(from: FSPath, to: FSPath) async throws
    func delete(_ paths: [FSPath]) async throws

    func copyInPlace(from: FSPath, to: FSPath) async throws

    /// Small head read for preview pane — bounded by `max` bytes.
    func readHead(_ path: FSPath, max: Int) async throws -> Data

    /// Full download to a local cache URL (for Quick Look / Open With).
    /// Providers may return the source URL directly when already local.
    func downloadToCache(_ path: FSPath) async throws -> URL

    /// Upload a local URL to remote path (cross-provider transfer entry).
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: (Int64) -> Void, cancel: CancelToken) async throws
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: (Int64) -> Void, cancel: CancelToken) async throws
}

/// Swift-side cancel token mirroring Rust's CancelFlag.
final class CancelToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
