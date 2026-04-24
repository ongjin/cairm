import Foundation

final class SshFileSystemProvider: FileSystemProvider {
    let identifier: ProviderID
    let displayScheme: String? = "ssh://"
    let supportsServerSideCopy: Bool

    private let pool: SftpHandleProviding
    private let target: SshTarget

    init(pool: SftpHandleProviding, target: SshTarget, supportsServerSideCopy: Bool = false) {
        self.pool = pool
        self.target = target
        self.identifier = .ssh(target)
        self.supportsServerSideCopy = supportsServerSideCopy
    }

    private func handle() async throws -> SftpHandleBridge {
        try await pool.sftpHandle(for: target)
    }

    private func isSessionDead(_ error: Error) -> Bool {
        let msg = (error as? RustString)?.toString() ?? "\(error)"
        return msg.contains("SFTP: session closed")
            || (msg.hasPrefix("Connection to ") && msg.contains(" lost"))
            || msg.hasPrefix("Russh: ")
            || msg.contains("SFTP: sftp timeout")
    }

    private func surface<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            if isSessionDead(error) {
                pool.invalidate(target)
            }
            throw error
        }
    }

    #if DEBUG
    func surfaceForTesting<T>(_ work: () async throws -> T) async throws -> T {
        try await surface(work)
    }
    #endif

    func list(_ path: FSPath) async throws -> [FileEntry] {
        try await surface {
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
    }

    func stat(_ path: FSPath) async throws -> FileStat {
        try await surface {
            let h = try await handle()
            let s = try sftp_stat(h, path.path)
            return FileStat(
                size: Int64(s.size),
                mtime: s.mtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(s.mtime)),
                mode: s.mode,
                isDirectory: s.is_dir
            )
        }
    }

    func exists(_ path: FSPath) async throws -> Bool {
        do {
            return try await surface {
                let h = try await handle()
                _ = try sftp_stat(h, path.path)
                return true
            }
        } catch {
            // Rust FFI surfaces `Result<_, String>` errors as RustString,
            // formatted by thiserror as "Not found: <msg>" for the SFTP
            // SSH_FX_NO_SUCH_FILE status (crates/cairn-ssh/src/error.rs:50).
            // Every other error — permission, timeout, connection-lost,
            // protocol — MUST rethrow so the paste-image rename loop can't
            // interpret a flaky session as "destination is free" and clobber
            // an existing remote file via uploadFromLocal's truncate.
            let msg = (error as? RustString)?.toString() ?? "\(error)"
            if msg.hasPrefix("Not found:") {
                return false
            }
            throw error
        }
    }

    func mkdir(_ path: FSPath) async throws {
        try await surface {
            let h = try await handle()
            try sftp_mkdir(h, path.path)
        }
    }

    func rename(from: FSPath, to: FSPath) async throws {
        try await surface {
            let h = try await handle()
            try sftp_rename(h, from.path, to.path)
        }
    }

    func delete(_ paths: [FSPath]) async throws {
        try await surface {
            let h = try await handle()
            for p in paths {
                try sftp_unlink(h, p.path)
            }
        }
    }

    func copyInPlace(from: FSPath, to: FSPath) async throws {
        try await surface {
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
            try await downloadToLocalWithoutSurface(from, toLocalURL: tmp, progress: { _ in }, cancel: cancel)
            try await uploadFromLocalWithoutSurface(tmp, to: to, progress: { _ in }, cancel: cancel)
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    func readHead(_ path: FSPath, max: Int) async throws -> Data {
        try await surface {
            let h = try await handle()
            let vec = try sftp_read_head(h, path.path, UInt32(max))
            return Data(bytes: vec.as_ptr(), count: vec.len())
        }
    }

    func downloadToCache(_ path: FSPath) async throws -> URL {
        try await RemoteCacheStore.shared.fetch(remotePath: path, via: self)
    }

    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        try await surface {
            try await uploadFromLocalWithoutSurface(localURL, to: remotePath, progress: progress, cancel: cancel)
        }
    }

    private func uploadFromLocalWithoutSurface(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
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
        try await runWithProgressPolling(
            poll: { Int64(sftp_progress_poll(h)) },
            sink: progress,
            work: { try sftp_upload_sync(h, localURL.path, remotePath.path, flag) }
        )
    }

    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        try await surface {
            try await downloadToLocalWithoutSurface(remotePath, toLocalURL: toLocalURL, progress: progress, cancel: cancel)
        }
    }

    private func downloadToLocalWithoutSurface(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
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
        try await runWithProgressPolling(
            poll: { Int64(sftp_progress_poll(h)) },
            sink: progress,
            work: { try sftp_download_sync(h, remotePath.path, toLocalURL.path, flag) }
        )
    }

    func walk(
        root: FSPath,
        pattern: String,
        maxDepth: Int,
        cap: Int,
        includeHidden: Bool,
        cancel: CancelToken
    ) -> AsyncThrowingStream<FileEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let h = try await handle()
                    let session = ssh_sftp_walk_start(
                        h,
                        root.path,
                        pattern,
                        UInt32(clamping: max(0, maxDepth)),
                        UInt32(clamping: max(0, cap)),
                        includeHidden
                    )
                    defer { ssh_sftp_walk_cancel(session) }

                    while !Task.isCancelled {
                        if cancel.isCancelled {
                            ssh_sftp_walk_cancel(session)
                            break
                        }

                        let batch = ssh_sftp_walk_drain(session, 200)
                        let count = sftp_walk_batch_len(batch)
                        for i in 0..<count {
                            let match = sftp_walk_batch_entry(batch, i)
                            continuation.yield(match.toFileEntry())
                        }

                        if ssh_sftp_walk_is_done(session), count == 0 {
                            break
                        }

                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func realpath(_ path: String) async throws -> String {
        try await surface {
            let h = try await handle()
            return try sftp_realpath(h, path).toString()
        }
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

private extension WalkMatchBridge {
    func toFileEntry() -> FileEntry {
        let nameStr = name.toString()
        return FileEntry(
            path: RustString(path.toString()),
            name: RustString(nameStr),
            size: UInt64(max(size, 0)),
            modified_unix: mtime,
            kind: is_directory ? .Directory : .Regular,
            is_hidden: nameStr.hasPrefix("."),
            icon_kind: is_directory ? .Folder : .GenericFile
        )
    }
}

// MARK: - Progress polling

/// Run `work` on a detached task while concurrently polling `poll` every
/// `interval` seconds and forwarding the returned value to `sink`.
/// Stops polling as soon as `work` completes (throws or returns). One extra
/// `sink` call at the end delivers the final byte count so a post-completion
/// UI read sees 100%.
@MainActor
func runWithProgressPolling(
    interval: Duration = .milliseconds(150),
    poll: @escaping () -> Int64,
    sink: @escaping (Int64) -> Void,
    work: @escaping @Sendable () async throws -> Void
) async throws {
    let workTask = Task.detached(priority: .userInitiated) {
        try await work()
    }

    let pollTask = Task { @MainActor in
        while !Task.isCancelled {
            sink(poll())
            try? await Task.sleep(for: interval)
        }
    }

    defer {
        pollTask.cancel()
        sink(poll())
    }

    _ = try await workTask.value
}
