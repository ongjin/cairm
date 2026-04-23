# Dual-pane split view (⌘⇧D)

Date: 2026-04-23
Scope: in-window vertical split so users can move files between two folder
views without juggling separate windows. Each pane has its own tabs, history,
and breadcrumb; the sidebar and Remote Hosts list stay shared.

## Goals

- ⌘⇧D toggles the split on/off.
- When split, left and right panes are independent: own tab list, own active
  tab, own back/forward history, own connect state.
- Clicking inside a pane's tab bar or file list marks it as the **active**
  pane. Menu commands (⌘T, ⌘W, ⌘N-for-new-tab-in-pane, ⌘1…9, ⌘← / ⌘→ / ⌘↑,
  ⌘[ / ⌘], ⇧⌘K Connect…) target the active pane.
- Sidebar is shared. Clicking a host/folder navigates the **active** pane.
- Drag-and-drop between panes reuses the existing `TransferController`
  (local→ssh, ssh→ssh, ssh→local already work cross-window; cross-pane is the
  same code path with different provider instances).

## Non-goals (v1)

- Horizontal split.
- More than two panes.
- Independent preview pane per side — one inspector on the window's right
  edge, tracking the active pane's selection.
- Resizable split ratio persisted across launches — 50/50 default, user can
  drag the divider per session but we don't persist.

## Architecture

### New: `WindowDualPaneModel` (per-window)

```swift
@Observable
final class WindowDualPaneModel {
    let left: WindowSceneModel          // always present
    private(set) var right: WindowSceneModel?  // nil when not split
    var activeSide: Side = .left
    enum Side { case left, right }

    var activePane: WindowSceneModel { activeSide == .right ? (right ?? left) : left }

    func toggleSplit(engine: CairnEngine, bookmarks: BookmarkStore, app: AppModel)
    func focus(_ side: Side)
}
```

- Owns two `WindowSceneModel` instances when split, one when not.
- Injected via `@Environment(WindowDualPaneModel.self)`.
- `toggleSplit` when activating seeds the right pane with a single tab cloning
  the left's current folder (matches ⌘T's clone-active-tab convention).
- Deactivating the split drops `right` entirely, calling `app.ssh.closeAll()`
  semantics is NOT invoked — sessions referenced only by the right pane's
  tabs get cleaned up by the existing `usedSshTargets` / 5-min idle reaper
  pipeline since `noteTabsChanged()` fires on every tab removal.

### Existing `WindowSceneModel` stays untouched

All per-pane behaviour is already there. The dual-pane model just holds two.

### `AppModel.sceneRefs` now tracks every live scene across both panes

Already weak-ref; `WindowDualPaneModel.toggleSplit` registers the right pane
with `app.register(scene:)` and lets the weak ref drop on deactivation.
`AppModel.usedSshTargets` iterates all registered scenes, so the sidebar dot
correctly reflects tabs across both panes.

### ContentView layout

Top-level body:

```
HSplitView (or GeometryReader + custom divider)
├─ Sidebar (shared, always on left)
└─ Detail area:
    - if right == nil: PaneColumn(pane: left)
    - else: HSplitView { PaneColumn(pane: left); PaneColumn(pane: right!) }
```

`PaneColumn` is a new subview that renders one pane's UI:
- Tab bar for that pane
- Toolbar strip under the tab bar (inline: sidebar-toggle is window-level, but
  back / forward / up + breadcrumb moves from the window toolbar into the
  pane's inline strip so each pane shows its own path).
- File list + empty/error states (extracted from existing `detailColumn`).

The window-level toolbar keeps: sidebar toggle (left), transfer HUD chip,
inspector toggle, and a new split-view toggle (⌘⇧D target). Back/forward/up
and breadcrumb move out of the window toolbar into each pane's inline strip.

### Focused values

`\.scene` continues to exist and is published from the active pane.
`ContentView` wires `.focusedSceneValue(\.scene, dualPane.activePane)`. Every
menu command that reads `@FocusedValue(\.scene)` automatically targets the
active pane — no downstream changes needed.

Pane activation: a tap gesture on each `PaneColumn`'s background calls
`dualPane.focus(side)`. Visual indicator: the inactive pane's tab bar dims
slightly (opacity 0.85) so the user can see which side is live.

### Keyboard / menu

- ⌘⇧D — Split/Unsplit (new "View" menu entry "Toggle Split View").
- ⌘⌥[ / ⌘⌥] — Focus Left Pane / Focus Right Pane (only enabled when split).
  Alternative: reuse ⌘⌥` (backtick) single-binding to cycle.
- All existing shortcuts (⌘T, ⌘W, ⌘1-9, ⌘←/→/↑, ⌘[ / ⌘], ⇧⌘K) route through
  `@FocusedValue(\.scene)` which now resolves to the active pane.

### Drag and drop

No code changes required: `TransferController` already dispatches based on
source/destination provider. Dragging a file from pane A's file list to pane
B's file list passes through the same `performDrop` path used today for
cross-window drops.

## Files touched

New:
- `apps/Sources/App/WindowDualPaneModel.swift`
- `apps/Sources/Views/PaneColumn.swift` (extracted from `ContentView.detailColumn`)

Modified:
- `apps/Sources/CairnApp.swift` — WindowScene owns DualPaneModel, publishes
  it + focused `\.scene`; new ⌘⇧D menu item; window toolbar slimmed down.
- `apps/Sources/ContentView.swift` — body renders one or two `PaneColumn`s,
  keeps shared sidebar; moves back/forward/up/breadcrumb out of window
  toolbar into pane inline strips.
- `apps/Sources/Views/Sidebar/SidebarView.swift` — all `scene.activeTab?`
  calls become `dualPane.activePane.activeTab?`. Silent-connect placeholder
  goes into the active pane.
- `apps/Sources/App/AppModel.swift` — no change; `register(scene:)` and
  `usedSshTargets` already handle arbitrary scene counts per window.

## Verification

1. **Toggle.** ⌘⇧D with a single-pane window → second pane appears on the
   right, seeded with a tab cloning the left's current folder. ⌘⇧D again →
   collapses back to single, left pane preserved.
2. **Independent state.** Open different folders in each pane; ⌘T in the
   active pane adds a tab only there; ⌘W closes only the active pane's tab.
   Back/forward histories are separate.
3. **Active pane focus.** Click inside the right pane's file list → tab bar
   highlight shifts right. ⌘T adds to right pane. Sidebar click on Home
   navigates right pane to ~/.
4. **Cross-pane drag.** Drag a local file from left pane to right pane's ssh
   view → `TransferController` enqueues an SFTP upload; the transfer HUD
   shows progress; file lands on the remote side on completion.
5. **SSH session reuse.** With both panes on the same ssh alias, closing the
   tab in one pane leaves the green sidebar dot on (the other pane still
   references the target). Closing the last tab on that host in both panes
   turns the dot gray but keeps the pool session warm per existing behaviour.
6. **Split collapse.** Toggling split off while right pane has open ssh tabs:
   those tabs' targets drop out of `usedSshTargets`, dot flips gray; pool
   sessions stay warm for 5 minutes.
