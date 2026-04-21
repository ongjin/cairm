import Foundation
import Observation
import SwiftUI

/// Top-level application state. Single instance injected via @Environment.
@Observable
final class AppModel {
    var history = NavigationHistory()
    var showHidden: Bool = false

    /// The bookmark entry currently "in use" (access started).
    /// nil until the user opens a folder.
    var currentEntry: BookmarkEntry?

    let engine: CairnEngine
    let bookmarks: BookmarkStore

    init(engine: CairnEngine = CairnEngine(), bookmarks: BookmarkStore = BookmarkStore()) {
        self.engine = engine
        self.bookmarks = bookmarks
    }

    /// The URL currently displayed (equal to history.current when present).
    var currentFolder: URL? { history.current }

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

        // Add to recent (unless this IS a recent-selection from sidebar — Phase 2 distinguishes).
        if entry.kind == .pinned {
            try? bookmarks.register(url, kind: .recent)
        }
    }

    /// Register a freshly-chosen folder (from NSOpenPanel) as pinned if first folder,
    /// otherwise as recent. Then navigate to it.
    func openAndNavigate(to url: URL, autoPinIfFirst: Bool = true) throws {
        let isFirst = bookmarks.pinned.isEmpty && autoPinIfFirst
        let entry = try bookmarks.register(url, kind: isFirst ? .pinned : .recent)
        navigate(to: entry)
    }

    /// Move up one level (parent directory). Requires the parent to be within the current
    /// security-scoped root — otherwise silently no-ops (Phase 1 limitation).
    func goUp() {
        guard let url = currentFolder else { return }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return } // at /

        // Phase 1: only walk within the current entry's access scope. If parent escapes,
        // user must re-open. Track is coarse — we simply let the listDirectory call fail
        // and show the error. Here we just push.
        history.push(parent)
    }

    func goBack() { _ = history.goBack() }
    func goForward() { _ = history.goForward() }

    func toggleShowHidden() {
        showHidden.toggle()
        engine.setShowHidden(showHidden)
    }
}
