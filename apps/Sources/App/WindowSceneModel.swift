import Foundation
import Observation

/// Per-window state container. Owns the list of Tabs and the currently active
/// one. Views in a window read state via `WindowSceneModel` from the
/// environment, distinct from the app-global `AppModel`.
///
/// New in M1.8 T10. A single WindowSceneModel is created per SwiftUI scene
/// (currently one WindowGroup → one scene). Multi-window support lands in T11.
@Observable
final class WindowSceneModel {
    private(set) var tabs: [Tab] = []
    var activeTabID: Tab.ID?

    let engine: CairnEngine
    let bookmarks: BookmarkStore

    init(engine: CairnEngine, bookmarks: BookmarkStore, initialURL: URL) {
        self.engine = engine
        self.bookmarks = bookmarks
        let first = Tab(engine: engine, bookmarks: bookmarks, initialURL: initialURL)
        self.tabs = [first]
        self.activeTabID = first.id
    }

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    /// Create a new tab. Defaults to cloning the active tab's current folder
    /// (matches Safari / Chrome `⌘T` inside a folder window behavior). Falls
    /// back to `$HOME` when there is no active tab or no current folder.
    func newTab(cloningActive: Bool = true) {
        let url: URL
        if cloningActive, let current = activeTab?.currentFolder {
            url = current
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
        }
        let t = Tab(engine: engine, bookmarks: bookmarks, initialURL: url)
        tabs.append(t)
        activeTabID = t.id
    }

    /// Open a new tab pointing at an SSH remote path using the given provider.
    func newRemoteTab(initialPath: FSPath, provider: FileSystemProvider) {
        let t = Tab(engine: engine, bookmarks: bookmarks, initialPath: initialPath, provider: provider)
        tabs.append(t)
        activeTabID = t.id
    }

    /// Remove the tab with `id`. If it was active, the last remaining tab
    /// becomes active; if no tabs remain, `activeTabID` is nil (the calling
    /// window should close in that case — T11).
    func closeTab(_ id: Tab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
    }

    func activateTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabID = tabs[index].id
    }

    func activatePrevious() {
        guard let cur = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        let prev = idx == 0 ? tabs.count - 1 : idx - 1
        activeTabID = tabs[prev].id
    }

    func activateNext() {
        guard let cur = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        let next = (idx + 1) % tabs.count
        activeTabID = tabs[next].id
    }
}
