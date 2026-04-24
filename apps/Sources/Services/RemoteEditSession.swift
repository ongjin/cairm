import Foundation

/// Lifecycle phases of a single remote edit session.
enum RemoteEditState: Equatable {
    case watching
    case uploading(Int64)
    case conflict
    case done
    case failed(String)
    case cancelled
}

/// One active remote edit. Held by RemoteEditController; disposed when the
/// user closes the chip entry or the upload completes.
final class RemoteEditSession {
    let id: UUID = UUID()
    let remotePath: FSPath
    let tempURL: URL
    let remoteMtimeAtDownload: Date
    var state: RemoteEditState

    init(remotePath: FSPath,
         tempURL: URL,
         remoteMtimeAtDownload: Date,
         state: RemoteEditState = .watching) {
        self.remotePath = remotePath
        self.tempURL = tempURL
        self.remoteMtimeAtDownload = remoteMtimeAtDownload
        self.state = state
    }
}
