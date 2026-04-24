import Foundation

/// Per-directory file system watcher built on `DispatchSource` (kqueue under
/// the hood). Fires `onChange` whenever the watched directory's immediate
/// entry list changes — entries added, removed, or renamed.
///
/// **Why not FSEventsStream?** The previous implementation used
/// `kFSEventStreamCreateFlagFileEvents` to recursively observe the current
/// folder's entire subtree. On macOS Sequoia, subscribing to a high-level
/// directory like `~` causes the kernel to report events from other apps'
/// container data (under `~/Library/Containers`, etc.) which trips the
/// "Cairn wants to access another app's data" TCC prompt — over and over,
/// for every external app write that lands inside the watched subtree.
///
/// `DispatchSource.makeFileSystemObjectSource` watches **a single file
/// descriptor** with no recursion, so we only see events for the directory
/// the user explicitly navigated into. The fd is opened with `O_EVTONLY`
/// which doesn't count as a "real" open and doesn't block unmount.
///
/// Tradeoff: deep changes (e.g. someone editing `~/workspace/work/daou/x.txt`
/// while we're sitting at `~`) won't trigger a reload. That's fine — the
/// file list only displays direct children, so deep edits don't change what
/// the user sees anyway.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fd: Int32
    private let onChange: () -> Void
    private var debounceWork: DispatchWorkItem?
    private var isSuspended: Bool = false

    init?(root: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let opened = open(root.path, O_EVTONLY)
        guard opened >= 0 else { return nil }
        self.fd = opened

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: opened,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.scheduleFire() }
        src.setCancelHandler { [opened] in close(opened) }
        src.resume()
        self.source = src
    }

    deinit {
        debounceWork?.cancel()
        source?.cancel()
    }

    /// Coalesce bursts of events (e.g. write tempfile → rename → flush) into
    /// a single reload. 80ms is short enough to feel instant, long enough to
    /// merge a typical save-file sequence.
    private func scheduleFire() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Stop delivering events while keeping the kqueue/fd alive.
    func pause() {
        guard !isSuspended else { return }
        source?.suspend()
        isSuspended = true
        debounceWork?.cancel()
    }

    /// Resume event delivery and trigger one refresh for changes missed while paused.
    func resume() {
        guard isSuspended else { return }
        source?.resume()
        isSuspended = false
        onChange()
    }
}
