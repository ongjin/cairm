import Foundation

/// Watches the ~/.ssh directory for changes (catching edits to ~/.ssh/config,
/// ~/.ssh/config.d/*, and any other files inside it) and fires a callback so
/// the sidebar can reload its host list.
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
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<ConfigFileWatcher>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ConfigFileWatcher>.fromOpaque(info).takeUnretainedValue().callback()
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
