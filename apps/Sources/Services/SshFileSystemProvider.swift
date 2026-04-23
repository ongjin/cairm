import Foundation

final class SshFileSystemProvider: FileSystemProvider {
    let identifier: ProviderID
    let displayScheme: String? = "ssh://"
    let supportsServerSideCopy: Bool

    private let pool: SshPoolService
    private let target: SshTarget

    init(pool: SshPoolService, target: SshTarget, supportsServerSideCopy: Bool = false) {
        self.pool = pool
        self.target = target
        self.identifier = .ssh(target)
        self.supportsServerSideCopy = supportsServerSideCopy
    }

    private func handle() async throws -> SftpHandleBridge {
        try await pool.sftpHandle(for: target)
    }

    func list(_ path: FSPath) async throws -> [FileEntry] {
        let h = try await handle()
        let listing = try sftp_list(h, path.path)
        let count = sftp_listing_len(listing)
        var entries: [FileEntry] = []
        entries.reserveCapacity(Int(count))
        for i in 0..<count {
            let e = sftp_listing_entry(listing, i)
            entries.append(e.toFileEntry(parent: path))
        }
        return entries
    }

    func stat(_ path: FSPath) async throws -> FileStat {
        let h = try await handle()
        let s = try sftp_stat(h, path.path)
        return FileStat(
            size: Int64(s.size),
            mtime: s.mtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(s.mtime)),
            mode: s.mode,
            isDirectory: s.is_dir
        )
    }

    func mkdir(_ path: FSPath) async throws {
        let h = try await handle()
        try sftp_mkdir(h, path.path)
    }

    func rename(from: FSPath, to: FSPath) async throws {
        let h = try await handle()
        try sftp_rename(h, from.path, to.path)
    }

    func delete(_ paths: [FSPath]) async throws {
        let h = try await handle()
        for p in paths {
            try sftp_unlink(h, p.path)
        }
    }

    func copyInPlace(from: FSPath, to: FSPath) async throws {
        // Client-mediated download → upload via a temp file.
        // Server-side copy-data extension is not in the v1 FFI surface.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-sftp-copy")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(from.lastComponent)
        try? FileManager.default.createDirectory(
            at: tmp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cancel = CancelToken()
        try await downloadToLocal(from, toLocalURL: tmp, progress: { _ in }, cancel: cancel)
        try await uploadFromLocal(tmp, to: to, progress: { _ in }, cancel: cancel)
        try? FileManager.default.removeItem(at: tmp)
    }

    func readHead(_ path: FSPath, max: Int) async throws -> Data {
        let h = try await handle()
        let vec = try sftp_read_head(h, path.path, UInt32(max))
        return Data(bytes: vec.as_ptr(), count: vec.len())
    }

    func downloadToCache(_ path: FSPath) async throws -> URL {
        try await RemoteCacheStore.shared.fetch(remotePath: path, via: self)
    }

    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: (Int64) -> Void, cancel: CancelToken) async throws {
        let h = try await handle()
        let flag = cancel_flag_new()
        let cancelTask = Task {
            while !Task.isCancelled {
                if cancel.isCancelled {
                    cancel_flag_cancel(flag)
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { cancelTask.cancel() }
        try sftp_upload_sync(h, localURL.path, remotePath.path, flag)
    }

    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: (Int64) -> Void, cancel: CancelToken) async throws {
        let h = try await handle()
        let flag = cancel_flag_new()
        let cancelTask = Task {
            while !Task.isCancelled {
                if cancel.isCancelled {
                    cancel_flag_cancel(flag)
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { cancelTask.cancel() }
        try sftp_download_sync(h, remotePath.path, toLocalURL.path, flag)
    }

    func realpath(_ path: String) async throws -> String {
        let h = try await handle()
        return try sftp_realpath(h, path).toString()
    }
}

private extension FileEntryBridge {
    func toFileEntry(parent: FSPath) -> FileEntry {
        let nameStr = name.toString()
        let base = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        let fullPath = base + nameStr
        let kind: FileKind = is_dir ? .Directory : .Regular
        let iconKind: IconKind = is_dir ? .Folder : .GenericFile
        return FileEntry(
            path: RustString(fullPath),
            name: RustString(nameStr),
            size: size,
            modified_unix: mtime,
            kind: kind,
            is_hidden: nameStr.hasPrefix("."),
            icon_kind: iconKind
        )
    }
}
