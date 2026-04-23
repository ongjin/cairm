import Foundation
import Observation

/// Per-window container for the single-pane or dual-pane split view layout.
/// Owns one or two `WindowSceneModel` instances and tracks which one is
/// currently the user's focus target — all @FocusedValue-driven menu
/// commands (⌘T, ⌘W, ⌘1-9, ⌘←/→/↑, ⌘[ / ⌘], ⇧⌘K) resolve through
/// `activePane` so they route to the side the user just interacted with.
///
/// The right pane is created on demand by `toggleSplit`, cloning the left
/// pane's current folder into its first tab (matches the ⌘T
/// clone-active-tab convention). Collapsing the split drops the right pane
/// entirely; any SSH sessions it referenced decay through the existing
/// `AppModel.usedSshTargets` pipeline + Rust's 5-min idle reaper.
@Observable
final class WindowDualPaneModel {
    enum Side { case left, right }

    let left: WindowSceneModel
    private(set) var right: WindowSceneModel?
    var activeSide: Side = .left

    var isSplit: Bool { right != nil }

    var activePane: WindowSceneModel {
        if activeSide == .right, let r = right { return r }
        return left
    }

    init(left: WindowSceneModel) {
        self.left = left
    }

    func focus(_ side: Side) {
        if side == .right, right == nil { return }
        activeSide = side
    }

    /// Toggle split on/off. On enable, seeds the right pane with a single tab
    /// mirroring the left pane's current folder. On disable, drops the right
    /// pane reference — AppModel's weak scene registry cleans up.
    func toggleSplit(engine: CairnEngine, bookmarks: BookmarkStore, app: AppModel) {
        if let _ = right {
            right = nil
            activeSide = .left
            app.noteTabsChanged()
            return
        }
        let seed: URL = left.activeTab?.currentFolder
            ?? FileManager.default.homeDirectoryForCurrentUser
        let pane = WindowSceneModel(engine: engine, bookmarks: bookmarks, initialURL: seed)
        pane.app = app
        app.register(scene: pane)
        right = pane
        activeSide = .right
        app.noteTabsChanged()
    }
}
