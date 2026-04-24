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
}
