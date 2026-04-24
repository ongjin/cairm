import Foundation
import Observation

/// Per-tab state container. One folder context lives here: FolderModel +
/// SearchModel + IndexService + GitService + NavigationHistory
/// + scoped-bookmark access.
///
/// Moved out of AppModel in M1.8 T10 so multi-tab / multi-window becomes
/// possible. AppModel now holds only app-global concerns; each window owns a
/// WindowSceneModel with `[Tab]`.
///
/// Scoped access: Tab owns the "currently scoped" BookmarkEntry and drives
/// start/stop against the shared BookmarkStore (which ref-counts internally).
/// Navigation helpers (`navigate`, `goBack`, `goForward`) preserve the exact
/// semantics of the pre-T10 AppModel so sandbox access behavior is unchanged.
@Observable
final class Tab: Identifiable {
    static var disableBackgroundServicesForTests = false

    let id = UUID()

    var connectionPhase: ConnectionPhase = .idle

    enum ConnectionPhase: Equatable {
        case idle
        /// Brand-new placeholder tab whose session has not yet been
        /// established. Carries the ssh_config alias so the empty-state view
        /// can show "Connecting to <alias>…" before any target is resolved.
        case establishing(alias: String)
        case connecting(detail: String)
        case connected
        case error(title: String, detail: String)
    }

    let folder: FolderModel
    let search: SearchModel
    /// Per-tab undo stack for file system mutations (drag-drop move, ⌘⌫
    /// trash, context-menu trash). Lives on the tab so each tab's history
    /// is independent — undoing in one tab won't surprise-resurrect a file
    /// you trashed in another. Wired to ⌘Z / ⌘⇧Z via the Edit menu in
    /// CairnApp's `CommandGroup(replacing: .undoRedo)`.
    let undoManager = UndoManager()

    private(set) var index: IndexService?
    /// Per-folder FSEventsStream watcher. Fires `folder.load(url)` whenever
    /// any file under the current folder changes — including changes WE made
    /// (drag/drop move, ⌘⌫, context-menu trash) and external ones (Finder,
    /// terminal). Replaces the old "rely on user to ⌘R" pattern.
    private var folderWatcher: FolderWatcher?
    /// Background tabs pause the watcher so they do not keep scheduling
    /// reloads the user cannot see.
    private(set) var isActive: Bool = true
    private(set) var git: GitService?

    var history = NavigationHistory()

    /// The active file system provider for this tab. Local tabs use
    /// `LocalFileSystemProvider`; remote tabs will use `SshFileSystemProvider`
    /// (added in Task 11). Stored as a class reference so it can be swapped
    /// when the tab reconnects to a different host.
    private(set) var provider: FileSystemProvider

    /// In-flight detached task that opens IndexService + GitService. Cancelled
    /// on a newer navigation so stale results never overwrite the current tab
    /// state.
    private var servicesTask: Task<Void, Never>?

    /// The bookmark entry currently "in use" (security-scoped access started).
    /// nil when we're in Home, a volume root, or an unscoped parent navigation.
    private(set) var currentEntry: BookmarkEntry?

    private let bookmarks: BookmarkStore
    private let engine: CairnEngine

    init(engine: CairnEngine, bookmarks: BookmarkStore, initialURL: URL) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.folder = FolderModel(engine: engine)
        self.search = SearchModel(engine: engine)
        self.provider = LocalFileSystemProvider(engine: engine)
        self.history.push(FSPath(provider: .local, path: initialURL.path))
        rebuildProviderServices(for: FSPath(provider: .local, path: initialURL.path))
    }

    /// Initializer for remote (SSH) tabs. The caller supplies a concrete
    /// `FileSystemProvider` instance and the starting `FSPath`.
    init(engine: CairnEngine, bookmarks: BookmarkStore, initialPath: FSPath, provider: FileSystemProvider) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.folder = FolderModel(engine: engine)
        self.search = SearchModel(engine: engine)
        self.provider = provider
        self.history.push(initialPath)
        rebuildProviderServices(for: initialPath)
    }

    deinit {
        servicesTask?.cancel()
        if let entry = currentEntry { bookmarks.stopAccessing(entry) }
    }

    /// The URL currently displayed. Returns nil for non-local providers —
    /// compatibility facade; prefer `currentPath` for new code.
    var currentFolder: URL? {
        guard let p = history.current, case .local = p.provider else { return nil }
        return URL(fileURLWithPath: p.path)
    }

    /// The FSPath currently displayed (equal to `history.current`).
    var currentPath: FSPath? { history.current }

    // MARK: - Navigation

    /// Navigate to a folder belonging to an already-bookmarked entry.
    /// Handles security-scoped start/stop ref-counting via BookmarkStore.
    /// On a pinned entry, also auto-registers to Recent (cheap heuristic —
    /// re-selecting from Recent won't add noise because kind != .pinned).
    func navigate(to entry: BookmarkEntry) {
        if let prev = currentEntry {
            bookmarks.stopAccessing(prev)
        }
        guard let url = bookmarks.startAccessing(entry) else {
            // Bookmark couldn't resolve — leave state unchanged, caller handles UI.
            return
        }
        currentEntry = entry
        let path = FSPath(provider: .local, path: url.path)
        history.push(path)
        rebuildProviderServices(for: path)

        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Swap this tab from an `.establishing` placeholder into a live remote
    /// tab pointing at `path`. Called from the sidebar silent-connect flow
    /// once `SshPool.connect` returns: before the call the tab showed the
    /// "Connecting…" spinner over a local no-op provider; after it the tab
    /// behaves like one opened directly via the Connect sheet.
    ///
    /// Clears `folder` before flipping the phase so the user never sees the
    /// local-home listing (loaded by the ContentView `.task` on placeholder
    /// creation) bleed through while the remote `onChange(currentPath)` load
    /// is still in flight. Stays on `.connecting` until the caller swaps to
    /// `.connected` — the connectingView keeps the spinner on screen through
    /// the remote directory fetch.
    func upgradeToRemote(path: FSPath, provider: FileSystemProvider) {
        self.provider = provider
        self.history = NavigationHistory()
        self.history.push(path)
        rebuildProviderServices(for: path)
        self.folder.clear()
        self.connectionPhase = .connecting(detail: "Loading remote directory…")
    }

    /// Navigate to an arbitrary FSPath. The canonical entry point for
    /// cross-provider navigation (local or SSH).
    func navigate(to path: FSPath) {
        if case .local = path.provider, let prev = currentEntry {
            bookmarks.stopAccessing(prev)
            currentEntry = nil
        }
        history.push(path)
        rebuildProviderServices(for: path)
    }

    /// Navigate to an arbitrary URL that we don't (yet) have a bookmark for.
    /// Drops any current scope. Used by breadcrumb parent segments and
    /// Locations items (volume roots, Trash, Network) — callers that KNOW
    /// the URL may lie outside the user-selected scope should prefer
    /// `AppModel.openAutoFavorite(url:in:)` which prompts on first use and
    /// reuses the registered bookmark afterwards.
    func navigate(to url: URL) {
        navigate(to: FSPath(provider: .local, path: url.path))
    }

    /// Move up one level. No-op at `/`.
    func goUp() {
        guard let cur = currentPath, let parent = cur.parent() else { return }
        navigate(to: parent)
    }

    @discardableResult
    func goBack() -> URL? {
        guard let path = history.goBack() else { return nil }
        resumeScopedAccessIfNeeded(for: path)
        rebuildProviderServices(for: path)
        guard case .local = path.provider else { return nil }
        return URL(fileURLWithPath: path.path)
    }

    @discardableResult
    func goForward() -> URL? {
        guard let path = history.goForward() else { return nil }
        resumeScopedAccessIfNeeded(for: path)
        rebuildProviderServices(for: path)
        guard case .local = path.provider else { return nil }
        return URL(fileURLWithPath: path.path)
    }

    // MARK: - Pinning

    /// `⌘D` and right-click "Add to Pinned" / "Unpin" enter here.
    /// No-op if there's no current folder.
    func toggleCurrentFolderPin() {
        guard let url = currentFolder else { return }
        try? bookmarks.togglePin(url: url)
    }

    // MARK: - Scoped access

    /// When history moves us to a URL that lives inside a pinned/recent
    /// bookmark's scope, reacquire that scope (stopping the previous one).
    /// Unscoped URLs drop the current scope. Prevents sandbox regression where
    /// a bookmarked folder's access was never resumed after ⌘←/⌘→.
    private func resumeScopedAccessIfNeeded(for path: FSPath) {
        guard case .local = path.provider else {
            // Remote paths have no sandbox scoping.
            if let prev = currentEntry {
                bookmarks.stopAccessing(prev)
                currentEntry = nil
            }
            return
        }
        let url = URL(fileURLWithPath: path.path)
        let stdPath = url.standardizedFileURL.path
        let match = bookmarks.pinned.first { $0.lastKnownPath == stdPath }
            ?? bookmarks.recent.first { $0.lastKnownPath == stdPath }

        if let prev = currentEntry, prev.id != match?.id {
            bookmarks.stopAccessing(prev)
            currentEntry = nil
        }
        if let entry = match, entry.id != currentEntry?.id {
            _ = bookmarks.startAccessing(entry)
            currentEntry = entry
        }
    }

    // MARK: - Services

    /// Routes to the appropriate service rebuild based on provider type.
    /// Index, Git and FolderWatcher are local-only — remote paths skip them.
    private func rebuildProviderServices(for path: FSPath) {
        if Self.disableBackgroundServicesForTests {
            servicesTask?.cancel()
            servicesTask = nil
            index = nil
            git = nil
            folderWatcher = nil
            return
        }
        if case .local = path.provider {
            rebuildServices(for: URL(fileURLWithPath: path.path))
        } else {
            // Remote tab: cancel any in-flight local services and clear them.
            servicesTask?.cancel()
            servicesTask = nil
            index = nil
            git = nil
            folderWatcher = nil
        }
    }

    /// Rebuilds per-folder services. IndexService and GitService both make
    /// synchronous FFI calls (tantivy open / libgit2 scan) that can take
    /// seconds on a large root — running them off the main thread keeps the
    /// UI responsive during navigation.
    ///
    /// Cancels any previous in-flight rebuild and guards against stale results
    /// by checking `currentFolder` equals the URL we opened before committing.
    private func rebuildServices(for url: URL) {
        let previous = servicesTask
        previous?.cancel()
        index = nil
        git = nil

        // Rebuild the FS watcher synchronously — a directory swap should
        // start observing the new root before the index task finishes,
        // otherwise external edits during indexing get missed.
        folderWatcher = FolderWatcher(root: url) { [weak self] in
            guard let self, let cur = self.currentFolder else { return }
            // Standardize the URL so a sandbox-resolved path matches the
            // raw one stored on the watcher.
            guard cur.standardizedFileURL.path == url.standardizedFileURL.path else { return }
            Task { await self.folder.load(cur) }
        }

        let target = url.standardizedFileURL
        // Open index + git in parallel. The index walk on a large root can
        // take a few seconds; running git after it would mean the Git column
        // stays hidden for that whole window even though `git status` itself
        // is sub-100ms. Two detached tasks let each surface the moment its
        // own work finishes.
        servicesTask = Task.detached { [weak self] in
            // Serialize FFI service opens for this Tab — wait for the
            // previous rebuild to fully release its IndexService/GitService
            // before opening new ones. Without this, a fast back/forward to
            // the same root can run two `ffi_index_open` calls concurrently
            // for the same redb file; redb rejects the second open with
            // `DatabaseAlreadyOpen`, the new task's `IndexService.init?`
            // returns nil, and the tab silently loses indexing until the
            // next navigation. `previous?.cancel()` above only signals — the
            // synchronous Rust FFI call inside `IndexService.init?` does not
            // observe Swift cancellation, so we must actually await
            // completion (which drops the old IndexService and releases the
            // redb file lock) before proceeding.
            _ = await previous?.value
            if Task.isCancelled { return }
            async let idxTask: IndexService? = Task.detached(priority: .userInitiated) {
                IndexService(root: url)
            }.value
            async let gitTask: GitService = Task.detached(priority: .userInitiated) {
                GitService(root: url)
            }.value
            let (idx, gitSvc) = await (idxTask, gitTask)
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.currentFolder?.standardizedFileURL.path == target.path else {
                    return
                }
                self.index = idx
                self.git = gitSvc
            }
        }
    }

    // MARK: - Tab activation

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            folderWatcher?.resume()
        } else {
            folderWatcher?.pause()
        }
    }
}

// MARK: - UI Helpers

extension Tab {
    /// Returns "SSH" when this tab is backed by a remote provider, nil for local.
    var protocolBadge: String? {
        if case .ssh = provider.identifier { return "SSH" }
        return nil
    }

    /// Human-readable title for the tab chip and window title bar.
    /// Remote tabs: "hostname:foldername". Local tabs: last path component.
    var titleText: String {
        guard let path = currentPath else { return "Tab" }
        if case .ssh(let t) = path.provider {
            let name = path.lastComponent.isEmpty ? "/" : path.lastComponent
            return "\(t.hostname):\(name)"
        }
        return path.lastComponent.isEmpty ? "/" : path.lastComponent
    }
}
