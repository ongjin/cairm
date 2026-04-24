import Foundation
import Darwin

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
    var onLocalChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?

    init(remotePath: FSPath,
         tempURL: URL,
         remoteMtimeAtDownload: Date,
         state: RemoteEditState = .watching) {
        self.remotePath = remotePath
        self.tempURL = tempURL
        self.remoteMtimeAtDownload = remoteMtimeAtDownload
        self.state = state
    }

    deinit {
        stopWatching()
    }

    /// Arm a file-descriptor watcher for writes to the local temp file.
    func startWatching() {
        guard source == nil else { return }

        let fd = open(tempURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.onLocalChange?()
        }
        src.setCancelHandler {
            close(fd)
        }
        source = src
        src.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }
}
