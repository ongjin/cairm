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
    let remoteEdit: RemoteEditController

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
        let transferController = MainActor.assumeIsolated { TransferController() }
        self.transfers = transferController
        self.remoteEdit = MainActor.assumeIsolated { RemoteEditController(transfers: transferController) }
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

    /// Finds an existing bookmark entry whose standardized path matches `url`.
    /// Auto-favorite taps prefer a previously-granted scoped bookmark so the
    /// ref-counted session in BookmarkStore keeps tracking correctly.
    static func lookupExistingBookmark(for url: URL, in store: BookmarkStore) -> BookmarkEntry? {
        let path = url.standardizedFileURL.path
        return store.pinned.first { $0.lastKnownPath == path }
            ?? store.recent.first { $0.lastKnownPath == path }
    }

    /// Classifies whether a sidebar auto-favorite URL must be acquired via
    /// NSOpenPanel on first use (so the Sandbox grants access via PowerBox
    /// and we can persist a security-scoped bookmark) vs. can be opened
    /// directly. Direct-open paths are:
    ///   - `/Applications` (not a TCC-gated folder)
    ///   - `~/Downloads` and its descendants (covered by the
    ///     `files.downloads.read-write` entitlement)
    /// Every other path — Desktop, Documents, Home, Pictures, Music, Movies,
    /// arbitrary roots — returns `true` so the panel path runs.
    static func autoFavoriteRequiresPicker(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path == "/Applications" || path.hasPrefix("/Applications/") { return false }
        let downloads = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .standardizedFileURL.path
        if path == downloads || path.hasPrefix(downloads + "/") { return false }
        return true
    }

    /// Sidebar auto-favorite tap handler. The goal is "one prompt ever, then
    /// silent": direct-open paths (Applications, Downloads) navigate without
    /// any dialog; protected paths (Desktop, Documents, Home, …) route through
    /// NSOpenPanel on first click — which is sandbox-native user consent, so
    /// macOS skips the `NSFooFolderUsageDescription` TCC prompt entirely — and
    /// persist the chosen URL as a security-scoped bookmark. Subsequent clicks
    /// resolve the bookmark and navigate silently.
    ///
    /// We register as `.recent` rather than `.pinned` because the auto-favorite
    /// row already occupies the sidebar's Favorites section; bouncing it into
    /// the pinned list would duplicate the visible entry.
    @MainActor
    func openAutoFavorite(url: URL, in tab: Tab) {
        if let existing = Self.lookupExistingBookmark(for: url, in: bookmarks) {
            tab.navigate(to: existing)
            return
        }
        if !Self.autoFavoriteRequiresPicker(url) {
            tab.navigate(to: url)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.message = "Grant Cairn access to \(url.lastPathComponent)."
        panel.prompt = "Grant Access"
        panel.begin { [weak self, weak tab] response in
            guard let self, let tab, response == .OK, let picked = panel.url else { return }
            if let entry = try? self.bookmarks.register(picked, kind: .recent) {
                tab.navigate(to: entry)
            } else {
                tab.navigate(to: picked)
            }
        }
    }

    // MARK: - Scene registry + SSH tab-usage view

    func register(scene: WindowSceneModel) {
        sceneRefs.append(WeakSceneRef(scene))
        sceneRefs.removeAll { $0.ref == nil }
    }

    @MainActor
    var activeScene: WindowSceneModel? {
        sceneRefs.removeAll { $0.ref == nil }
        return sceneRefs.last?.ref
    }

    /// Bumps a dummy observable so SwiftUI views that read `usedSshTargets`
    /// redraw. Called from WindowSceneModel after tab list changes — cheaper
    /// and safer than racing a pool disconnect, which we deliberately DO NOT
    /// do here: keeping the session warm lets slow-to-boot hosts (cloudflared
    /// ProxyCommand) re-attach instantly when the user clicks the sidebar
    /// entry again. The pool's 5-min idle reaper reclaims truly-dead sessions.
    var tabUsageRevision: Int = 0

    func noteTabsChanged() { tabUsageRevision &+= 1 }

    /// Set of SshTargets referenced by at least one live tab across all
    /// windows. The sidebar uses this — NOT `ssh.sessions` — to decide which
    /// Remote Hosts rows show a green dot, so closing the last tab on a host
    /// flips the dot immediately even though the pool session lingers.
    @MainActor
    var usedSshTargets: Set<SshTarget> {
        _ = tabUsageRevision  // tracked by @Observable so mutations re-render
        sceneRefs.removeAll { $0.ref == nil }
        var out: Set<SshTarget> = []
        for box in sceneRefs {
            guard let s = box.ref else { continue }
            for tab in s.tabs {
                if let p = tab.currentPath, case .ssh(let t) = p.provider {
                    out.insert(t)
                }
            }
        }
        return out
    }
}

private final class WeakSceneRef {
    weak var ref: WindowSceneModel?
    init(_ s: WindowSceneModel) { self.ref = s }
}
