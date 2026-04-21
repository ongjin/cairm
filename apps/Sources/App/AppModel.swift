import Foundation
import Observation
import SwiftUI

/// Top-level application state. Single instance injected via @Environment.
///
/// M1.3 additions:
///   - `sidebar` / `mountObserver` so Views can observe via the same AppModel.
///   - `lastFolder` to persist the current folder across launches.
///   - `bootstrapInitialFolder()` — runs at end of init to restore lastFolder
///     or fall back to Home. No more OpenFolderEmptyState gate.
@Observable
final class AppModel {
    var history = NavigationHistory()
    var showHidden: Bool = false

    /// The bookmark entry currently "in use" (security-scoped access started).
    /// nil when we're in Home or a volume root that doesn't need bookmarking
    /// (dev builds bypass sandbox; under sandbox this will need a bookmark in M1.6).
    var currentEntry: BookmarkEntry?

    let engine: CairnEngine
    let bookmarks: BookmarkStore
    let lastFolder: LastFolderStore
    let mountObserver: MountObserver
    let sidebar: SidebarModel

    init(engine: CairnEngine = CairnEngine(),
         bookmarks: BookmarkStore = BookmarkStore(),
         lastFolder: LastFolderStore = LastFolderStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
        self.lastFolder = lastFolder
        let observer = MountObserver()
        self.mountObserver = observer
        self.sidebar = SidebarModel(mountObserver: observer)
        bootstrapInitialFolder()
    }

    /// The URL currently displayed (equal to history.current when present).
    var currentFolder: URL? { history.current }

    // MARK: - Bootstrap

    /// Restores the last-viewed folder, falling back to the user's home
    /// directory. Called once at the end of init — after this returns,
    /// `currentFolder` is guaranteed non-nil for the lifetime of the app
    /// (absent user action that clears history, which Phase 1 doesn't expose).
    private func bootstrapInitialFolder() {
        let url = lastFolder.load() ?? FileManager.default.homeDirectoryForCurrentUser
        history.push(url)
    }

    // MARK: - Navigation

    /// Navigate to a folder belonging to an already-bookmarked entry.
    /// Handles security-scoped start/stop ref-counting via BookmarkStore.
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

        // Add to recent unless the user is explicitly re-selecting from the
        // Recent section — cheap heuristic: only auto-add when entering from pin.
        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Navigate to an arbitrary URL that we don't (yet) have a bookmark for.
    /// Used by sidebar Locations items (Computer root, mounted volumes) and by
    /// the default-landing bootstrap. Under sandbox this will fail at
    /// listDirectory time and surface a `.failed` state — M1.6 polishes that.
    func navigateUnscoped(to url: URL) {
        if let prev = currentEntry {
            bookmarks.stopAccessing(prev)
            currentEntry = nil
        }
        history.push(url)
    }

    /// Register a freshly-chosen folder (from NSOpenPanel) as pinned if it's the
    /// user's very first folder, otherwise as recent. Then navigate to it.
    func openAndNavigate(to url: URL, autoPinIfFirst: Bool = true) throws {
        let isFirst = bookmarks.pinned.isEmpty && autoPinIfFirst
        let entry = try bookmarks.register(url, kind: isFirst ? .pinned : .recent)
        navigate(to: entry)
    }

    /// Move up one level. No-op at `/`.
    func goUp() {
        guard let url = currentFolder else { return }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return }
        history.push(parent)
    }

    func goBack() {
        guard let url = history.goBack() else { return }
        resumeScopedAccessIfNeeded(for: url)
    }

    func goForward() {
        guard let url = history.goForward() else { return }
        resumeScopedAccessIfNeeded(for: url)
    }

    /// When history moves us to a URL that lives inside a pinned bookmark's
    /// scope, reacquire that scope (stopping the previous one). Unscoped URLs
    /// drop the current scope. Prevents M1.6 sandbox regression where a
    /// bookmarked folder's access was never resumed after ⌘←/⌘→.
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

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }

    // MARK: - Pinning

    /// `⌘D` and right-click "Add to Pinned" / "Unpin" enter here.
    /// No-op if there's no current folder (shouldn't happen after bootstrap).
    func toggleCurrentFolderPin() {
        guard let url = currentFolder else { return }
        try? bookmarks.togglePin(url: url)
    }
}
