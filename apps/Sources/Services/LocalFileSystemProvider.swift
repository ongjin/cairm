import Foundation

final class LocalFileSystemProvider: FileSystemProvider {
    let identifier: ProviderID = .local
    let displayScheme: String? = nil
    let supportsServerSideCopy: Bool = true

    private let engine: CairnEngine

    init(engine: CairnEngine) { self.engine = engine }

    func list(_ path: FSPath) async throws -> [FileEntry] {
        try await engine.listDirectory(URL(fileURLWithPath: path.path))
    }

    func stat(_ path: FSPath) async throws -> FileStat {
        let url = URL(fileURLWithPath: path.path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        let mode = (try? FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.uint32Value ?? 0
        return FileStat(
            size: Int64(values.fileSize ?? 0),
            mtime: values.contentModificationDate,
            mode: mode,
            isDirectory: values.isDirectory ?? false
        )
    }

    func mkdir(_ path: FSPath) async throws {
        try FileManager.default.createDirectory(atPath: path.path, withIntermediateDirectories: false)
    }

    func rename(from: FSPath, to: FSPath) async throws {
        try FileManager.default.moveItem(atPath: from.path, toPath: to.path)
    }

    func delete(_ paths: [FSPath]) async throws {
        for p in paths {
            let url = URL(fileURLWithPath: p.path)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    func copyInPlace(from: FSPath, to: FSPath) async throws {
        try FileManager.default.copyItem(atPath: from.path, toPath: to.path)
    }

    func readHead(_ path: FSPath, max: Int) async throws -> Data {
        let url = URL(fileURLWithPath: path.path)
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        return try h.read(upToCount: max) ?? Data()
    }

    func downloadToCache(_ path: FSPath) async throws -> URL {
        URL(fileURLWithPath: path.path)    // local: already accessible
    }

    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: (Int64) -> Void, cancel: CancelToken) async throws {
        // Local → local "upload" = copy
        try FileManager.default.copyItem(at: localURL, to: URL(fileURLWithPath: remotePath.path))
    }

    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: (Int64) -> Void, cancel: CancelToken) async throws {
        try FileManager.default.copyItem(at: URL(fileURLWithPath: remotePath.path), to: toLocalURL)
    }
}
