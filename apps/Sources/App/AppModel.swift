import AppKit
import Foundation
import Observation
import SwiftUI

/// Top-level application state. Single instance injected via @Environment.
///
/// M1.8 T10 shape:
///   - Holds ONLY app-global concerns (engine, bookmarks, sidebar, mount
///     observer, lastFolder, showHidden, NSOpenPanel relaunch).
///   - Per-window / per-tab state (history, currentFolder, preview, scoped
///     bookmark access, navigation helpers) lives on `Tab` /
///     `WindowSceneModel`.
///   - `bootstrapInitialURL()` returns the starting URL — consumed by
///     `WindowScene` when it builds the scene's first Tab.
@Observable
final class AppModel {
    var showHidden: Bool

    let engine: CairnEngine
    let bookmarks: BookmarkStore
    let lastFolder: LastFolderStore
    let settings: SettingsStore
    let mountObserver: MountObserver
    let sidebar: SidebarModel
    let ssh: SshPoolService
    let sshConfig: SshConfigService
    let transfers: TransferController

    /// Weakly-held references to every live `WindowSceneModel` so that SSH
    /// session reconciliation (disconnect on last-tab-close) can see tabs
    /// across all windows — not just the one that triggered closeTab.
    @ObservationIgnored private var sceneRefs: [WeakSceneRef] = []

    init(engine: CairnEngine = CairnEngine(),
         bookmarks: BookmarkStore = BookmarkStore(),
         lastFolder: LastFolderStore = LastFolderStore(),
         settings: SettingsStore = SettingsStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.lastFolder = lastFolder
        self.settings = settings
        let observer = MountObserver()
        self.mountObserver = observer
        self.sidebar = SidebarModel(mountObserver: observer)
        self.ssh = SshPoolService()
        let metadataStore = HostMetadataStore()
        self.sshConfig = MainActor.assumeIsolated { SshConfigService(metadata: metadataStore) }
        self.transfers = MainActor.assumeIsolated { TransferController() }
        // Seed hidden-files default from settings; keeps Rust engine in sync.
        self.showHidden = settings.showHiddenByDefault
        engine.setShowHidden(settings.showHiddenByDefault)

        // Graceful quit: close all SSH sessions.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ssh.closeAll()
        }
    }

    // MARK: - Bootstrap

    /// Starting URL for a freshly-opened window. Falls back to `$HOME` if the
    /// persisted path no longer exists (handled inside LastFolderStore).
    func bootstrapInitialURL() -> URL {
        switch settings.startFolder {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .lastUsed:
            return lastFolder.load() ?? FileManager.default.homeDirectoryForCurrentUser
        }
    }

    // MARK: - Show hidden

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }

    // MARK: - NSOpenPanel relaunch

    /// Re-prompts the user for folder access via `NSOpenPanel`. Invoked from
    /// the "Grant Access…" button in the permission-denied empty state.
    /// The caller's `onPick` decides how to consume the URL — if the user
    /// re-selects the *same* folder, `Tab.navigate` alone does not refire
    /// ContentView's `onChange` (same value), so the caller needs the option
    /// to force a reload.
    ///
    /// This stays on AppModel because it's a global UI concern (NSOpenPanel,
    /// no tab state). The caller threads in the current folder from the
    /// active Tab.
    @MainActor
    func reopenFolder(startingAt current: URL?, onPick: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let current {
            panel.directoryURL = current
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                onPick(url)
            }
        }
    }

    // MARK: - Bookmark helpers

    /// Register a freshly-chosen folder (from NSOpenPanel) as pinned if it's
    /// the user's very first folder, otherwise as recent. Returns the created
    /// bookmark entry — caller typically passes it to `Tab.navigate(to:)`.
    @discardableResult
    func registerOpenedFolder(_ url: URL, autoPinIfFirst: Bool = true) throws -> BookmarkEntry {
        let isFirst = bookmarks.pinned.isEmpty && autoPinIfFirst
        return try bookmarks.register(url, kind: isFirst ? .pinned : .recent)
    }

    // MARK: - Scene registry + SSH session lifecycle

    func register(scene: WindowSceneModel) {
        sceneRefs.append(WeakSceneRef(scene))
        sceneRefs.removeAll { $0.ref == nil }
    }

    /// Compute which SSH targets are still referenced by some live tab across
    /// all windows, then disconnect any pool session that's no longer in use.
    /// Called from WindowSceneModel.closeTab so the sidebar dot flips off as
    /// soon as the last tab on a host is gone — the 5-minute Rust idle reaper
    /// still backs this up for edge cases (window closed via red-dot, etc.).
    @MainActor
    func reconcileSshSessions() {
        sceneRefs.removeAll { $0.ref == nil }
        var inUse: Set<SshTarget> = []
        for box in sceneRefs {
            guard let s = box.ref else { continue }
            for tab in s.tabs {
                if let p = tab.currentPath, case .ssh(let t) = p.provider {
                    inUse.insert(t)
                }
            }
        }
        for target in Array(ssh.sessions.keys) where !inUse.contains(target) {
            ssh.disconnect(target)
        }
    }
}

private final class WeakSceneRef {
    weak var ref: WindowSceneModel?
    init(_ s: WindowSceneModel) { self.ref = s }
}
