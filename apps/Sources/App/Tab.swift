import Foundation
import Observation

/// Per-tab state container. One folder context lives here: FolderModel +
/// SearchModel + PreviewModel + IndexService + GitService + NavigationHistory
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
    let id = UUID()

    let folder: FolderModel
    let search: SearchModel
    let preview: PreviewModel
    private(set) var index: IndexService?
    private(set) var git: GitService?

    var history = NavigationHistory()

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
        self.preview = PreviewModel(engine: engine)
        self.history.push(initialURL)
        rebuildServices(for: initialURL)
    }

    deinit {
        servicesTask?.cancel()
        if let entry = currentEntry { bookmarks.stopAccessing(entry) }
    }

    /// The URL currently displayed (equal to `history.current` when present).
    var currentFolder: URL? { history.current }

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
        history.push(url)
        rebuildServices(for: url)

        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Navigate to an arbitrary URL that we don't (yet) have a bookmark for.
    /// Drops any current scope. Used by sidebar Locations items and breadcrumb
    /// parent segments.
    func navigate(to url: URL) {
        if let prev = currentEntry {
            bookmarks.stopAccessing(prev)
            currentEntry = nil
        }
        history.push(url)
        rebuildServices(for: url)
    }

    /// Move up one level. No-op at `/`.
    func goUp() {
        guard let cur = currentFolder else { return }
        let parent = cur.deletingLastPathComponent()
        guard parent.path != cur.path else { return }
        navigate(to: parent)
    }

    @discardableResult
    func goBack() -> URL? {
        guard let url = history.goBack() else { return nil }
        resumeScopedAccessIfNeeded(for: url)
        rebuildServices(for: url)
        return url
    }

    @discardableResult
    func goForward() -> URL? {
        guard let url = history.goForward() else { return nil }
        resumeScopedAccessIfNeeded(for: url)
        rebuildServices(for: url)
        return url
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
    private func resumeScopedAccessIfNeeded(for url: URL) {
        let path = url.standardizedFileURL.path
        let match = bookmarks.pinned.first { $0.lastKnownPath == path }
            ?? bookmarks.recent.first { $0.lastKnownPath == path }

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

    /// Rebuilds per-folder services. IndexService and GitService both make
    /// synchronous FFI calls (tantivy open / libgit2 scan) that can take
    /// seconds on a large root — running them off the main thread keeps the
    /// UI responsive during navigation.
    ///
    /// Cancels any previous in-flight rebuild and guards against stale results
    /// by checking `currentFolder` equals the URL we opened before committing.
    private func rebuildServices(for url: URL) {
        servicesTask?.cancel()
        index = nil
        git = nil

        let target = url.standardizedFileURL
        servicesTask = Task.detached { [weak self] in
            let idx = IndexService(root: url)
            let gitSvc = GitService(root: url)
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
}
