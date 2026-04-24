import Foundation
import Observation

enum UploadOutcome: Equatable {
    case uploaded
    case conflict
    case failed(String)
    case cancelled
}

@MainActor
@Observable
final class RemoteEditController {
    private(set) var activeSessions: [UUID: RemoteEditSession] = [:]

    private let transfers: TransferController
    private let workRoot: URL
    @ObservationIgnored private var pendingUploads: [UUID: Task<Void, Never>] = [:]

    private static let debounceMs: UInt64 = 800
    private static let maxEditableBytes: Int64 = 50 * 1024 * 1024

    init(transfers: TransferController,
         workRoot: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Cairn/RemoteEdit")) {
        self.transfers = transfers
        self.workRoot = workRoot
        try? FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
    }

    func beginSession(remotePath: FSPath, via provider: FileSystemProvider) async throws -> RemoteEditSession {
        let stat = try await provider.stat(remotePath)
        if stat.size > Self.maxEditableBytes {
            throw NSError(
                domain: "Cairn.RemoteEdit",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "File is too large for edit-in-place (>50 MiB). Download manually instead."
                ]
            )
        }

        let sessionDir = workRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let tempURL = sessionDir.appendingPathComponent(remotePath.lastComponent)

        try await provider.downloadToLocal(
            remotePath,
            toLocalURL: tempURL,
            progress: { _ in },
            cancel: CancelToken()
        )

        let session = RemoteEditSession(
            remotePath: remotePath,
            tempURL: tempURL,
            remoteMtimeAtDownload: stat.mtime ?? .distantPast
        )
        activeSessions[session.id] = session
        return session
    }

    func uploadSession(_ id: UUID,
                       via provider: FileSystemProvider,
                       onConflictResolve: ((RemoteEditSession) async -> Bool)? = nil) async throws -> UploadOutcome {
        guard let session = activeSessions[id] else {
            return .failed("no such session")
        }

        let fresh = try await provider.stat(session.remotePath)
        if let remoteNow = fresh.mtime,
           remoteNow > session.remoteMtimeAtDownload.addingTimeInterval(1) {
            session.state = .conflict
            if let resolve = onConflictResolve {
                guard await resolve(session) else { return .conflict }
            } else {
                return .conflict
            }
        }

        session.state = .uploading(0)
        do {
            try await provider.uploadFromLocal(
                session.tempURL,
                to: session.remotePath,
                progress: { bytes in
                    Task { @MainActor in
                        session.state = .uploading(bytes)
                    }
                },
                cancel: CancelToken()
            )
            session.state = .done
            return .uploaded
        } catch {
            let message = String(describing: error)
            session.state = .failed(message)
            return .failed(message)
        }
    }

    func armWatching(for id: UUID,
                     via provider: FileSystemProvider,
                     onConflictResolve: ((RemoteEditSession) async -> Bool)? = nil) {
        guard let session = activeSessions[id] else { return }
        session.onLocalChange = { [weak self] in
            self?.scheduleUpload(
                id: id,
                via: provider,
                onConflictResolve: onConflictResolve
            )
        }
        session.startWatching()
    }

    private func scheduleUpload(id: UUID,
                                via provider: FileSystemProvider,
                                onConflictResolve: ((RemoteEditSession) async -> Bool)? = nil) {
        pendingUploads[id]?.cancel()
        pendingUploads[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMs * 1_000_000)
            if Task.isCancelled { return }
            _ = try? await self?.uploadSession(
                id,
                via: provider,
                onConflictResolve: onConflictResolve
            )
        }
    }

    func endSession(_ id: UUID) {
        guard let session = activeSessions[id] else { return }
        session.stopWatching()
        pendingUploads[id]?.cancel()
        pendingUploads.removeValue(forKey: id)
        let dir = session.tempURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        activeSessions.removeValue(forKey: id)
    }

    func endSessionsForHost(_ target: SshTarget) {
        let ids = activeSessions.compactMap { id, session in
            session.remotePath.provider == .ssh(target) ? id : nil
        }
        for id in ids {
            endSession(id)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            for id in Array(activeSessions.keys) {
                endSession(id)
            }
        }
    }
}
