import Foundation
import Observation

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
}
