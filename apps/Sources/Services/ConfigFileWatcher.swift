import Foundation

/// Watches ~/.ssh/config (+ first-level ~/.ssh/config.d/* glob) for changes
/// and fires a callback so the sidebar can reload its host list.
final class ConfigFileWatcher {
    private let callback: () -> Void
    private var stream: FSEventStreamRef?

    init(callback: @escaping () -> Void) {
        self.callback = callback
        start()
    }

    deinit { stop() }

    private func start() {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return }
        let paths: [String] = [
            "\(home)/.ssh/config",
            "\(home)/.ssh/config.d",
        ]
        // FSEvents wants directories; if config file is watched, use its parent.
        let watchDirs = Array(Set(paths.map { ($0 as NSString).deletingLastPathComponent }))
        let pathsCF = watchDirs as CFArray
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let w = Unmanaged<ConfigFileWatcher>.fromOpaque(info).takeUnretainedValue()
            w.callback()
        }
        stream = FSEventStreamCreate(
            nil, cb, &context, pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        if let s = stream {
            FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
            FSEventStreamStart(s)
        }
    }

    private func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
        stream = nil
    }
}
