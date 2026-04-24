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
    var activeTabID: Tab.ID? {
        didSet { reconcileActiveFlags() }
    }

    /// Connect-to-Server sheet state for this window. Non-nil while the sheet
    /// is presented; set by the sidebar or the ⇧⌘K menu on the focused window,
    /// cleared on cancel/success. Per-scene so a second window's sheet can't
    /// piggyback on another window's invocation.
    var connectSheetModel: ConnectSheetModel?

    let engine: CairnEngine
    let bookmarks: BookmarkStore
    /// Weak to break the retain cycle: AppModel weakly tracks scenes, and a
    /// scene needs to call back into AppModel on closeTab to release SSH
    /// sessions that no remaining tab references.
    @ObservationIgnored weak var app: AppModel?

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
        reconcileActiveFlags()
    }

    /// Create a new local tab at a specific URL. Used by external entry points
    /// that should not clone the currently-active folder.
    func newTab(initialURL: URL) {
        let t = Tab(engine: engine, bookmarks: bookmarks, initialURL: initialURL)
        tabs.append(t)
        activeTabID = t.id
        reconcileActiveFlags()
    }

    /// Open a new tab pointing at an SSH remote path using the given provider.
    func newRemoteTab(initialPath: FSPath, provider: FileSystemProvider) {
        let t = Tab(engine: engine, bookmarks: bookmarks, initialPath: initialPath, provider: provider)
        tabs.append(t)
        activeTabID = t.id
        reconcileActiveFlags()
    }

    /// Create a placeholder tab showing the "Connecting to <alias>…" spinner
    /// while the pool negotiates the session. Caller later invokes
    /// `upgradeToRemote` on the returned tab (on success) or mutates its
    /// `connectionPhase` to `.error` (on failure) so the existing
    /// RemoteErrorCard surfaces Retry / Edit ssh_config / Open Terminal.
    @discardableResult
    func newEstablishingTab(alias: String) -> Tab {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let t = Tab(engine: engine, bookmarks: bookmarks, initialURL: home)
        t.connectionPhase = .establishing(alias: alias)
        tabs.append(t)
        activeTabID = t.id
        reconcileActiveFlags()
        return t
    }

    /// Remove the tab with `id`. If it was active, the last remaining tab
    /// becomes active; if no tabs remain, `activeTabID` is nil (the calling
    /// window should close in that case — T11).
    func closeTab(_ id: Tab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closedProvider = tabs[idx].currentPath?.provider
        tabs.remove(at: idx)
        if case .ssh(let target) = closedProvider {
            MainActor.assumeIsolated {
                app?.remoteEdit.endSessionsForHost(target)
            }
        }
        if activeTabID == id {
            activeTabID = tabs.last?.id
        }
        reconcileActiveFlags()
        // Notify AppModel so the sidebar dot flips off when the last tab on a
        // host closes. We do NOT disconnect the pool session here — that would
        // force a fresh handshake (and slow ProxyCommand boot) on the next
        // reconnect. Rust's 5-min idle reaper handles true cleanup.
        app?.noteTabsChanged()
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

    private func reconcileActiveFlags() {
        for tab in tabs {
            tab.setActive(tab.id == activeTabID)
        }
    }
}
