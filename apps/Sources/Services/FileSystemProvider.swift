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
    /// Existence probe that only returns `false` on an explicit "not found"
    /// result. Transport, permission, or protocol errors MUST rethrow so
    /// callers (e.g. the paste-image rename loop) don't treat a flaky
    /// session as "destination is free" and truncate a real file.
    func exists(_ path: FSPath) async throws -> Bool
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
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws

    /// Resolve a path to its absolute canonical form on the provider. For SSH,
    /// this is a server-side call used to expand "~" / "." to the real home dir.
    func realpath(_ path: String) async throws -> String

    /// Recursive name-substring walk. Providers that cannot stream should use
    /// the default unsupported implementation so callers can fall back.
    func walk(
        root: FSPath,
        pattern: String,
        maxDepth: Int,
        cap: Int,
        includeHidden: Bool,
        cancel: CancelToken
    ) -> AsyncThrowingStream<FileEntry, Error>
}

enum FileSystemError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Operation unsupported by this provider"
        }
    }
}

extension FileSystemProvider {
    func walk(
        root: FSPath,
        pattern: String,
        maxDepth: Int,
        cap: Int,
        includeHidden: Bool,
        cancel: CancelToken
    ) -> AsyncThrowingStream<FileEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: FileSystemError.unsupported)
        }
    }
}

/// Swift-side cancel token mirroring Rust's CancelFlag.
final class CancelToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
