# UI polish: drop sidebar Recent · ⌘[ / ⌘] nav · per-window Connect sheet

Date: 2026-04-23
Scope: three small UI issues reported against current `main` (865f3ec).

## 1. Remove sidebar "Recent" section

**Problem.** Sidebar currently shows a Recent section populated from `BookmarkStore.recent`. Finder-replacement pivot deprioritises this — pinned Favorites and Remote Hosts cover the real access patterns.

**Change.** In `apps/Sources/Views/Sidebar/SidebarView.swift`:
- Delete the `Section("Recent")` block and the `recentRow` helper.
- Update the file-level doc comment to drop the Recent reference.
- Touch up `SidebarModel.swift` doc comment similarly.

**Out of scope.** `BookmarkStore.recent` data model and its recording call-sites stay. Removing the UI does not require ripping out the model, and leaving it in place keeps the door open if we later surface it in Command Palette or similar.

## 2. Mouse side-button → history back/forward

**Problem.** User reports side-button back is not working. An NSEvent monitor for `.otherMouseDown` (buttons 3/4) is already installed at `ContentView.swift:127-141` and calls `tab.goBack/goForward`. It looks correct. The likely failure mode is that some mice/drivers rewrite the side buttons into keyboard shortcuts (⌘[, ⌘]) instead of emitting `.otherMouseDown` — in which case the NSEvent monitor never fires.

**Change.** Add ⌘[ / ⌘] as menu-bound shortcuts for Back / Forward (Finder parity). Keep the existing NSEvent monitor as the native path for hardware that emits real mouse events.

- Navigate menu (`CairnApp.swift`) gains two items: "Back" (⌘[) and "Forward" (⌘]), each routing through `scene.activeTab?.goBack() / goForward()`, disabled when the tab cannot go back/forward.
- Existing ⌘←/⌘→ toolbar button shortcuts stay (they're typed on the toolbar Buttons, not the menu).
- Existing NSEvent monitor stays unchanged.

**Why both.** The monitor covers real side-button events; the menu shortcuts cover driver-rewritten ones. Together they match how Chrome/Finder behave for every common mouse.

## 3. Connect-to-Server sheet opens on all windows

**Problem.** Clicking "Connect…" or a disconnected host in the sidebar, or pressing ⇧⌘K, posts `.openConnectSheet` on `NotificationCenter.default`. Every `ContentView` subscribes, so with two windows open both show the sheet.

**Root cause.** Broadcast notification, no scene filter.

**Change.** Replace notification-based delivery with per-scene state.

- Add `var connectSheetModel: ConnectSheetModel?` to `WindowSceneModel`.
- `ContentView` binds its `.sheet(item:)` to `$scene.connectSheetModel` (via `@Bindable`) instead of the local `@State` + notification listener. Drop the `@State private var connectSheetModel` and the `.onReceive(...openConnectSheet)` subscription.
- `SidebarView.openConnectSheet` / `connectHost` set `scene.connectSheetModel` directly.
- Menu item "Connect to Server…" (⇧⌘K) uses the existing `FocusedValues.scene` key (already published from `CairnApp.swift:72`). `ConnectFileMenuItems` reads `@FocusedValue(\.scene)` and sets `scene?.connectSheetModel = ConnectSheetModel()`.
- Delete the `Notification.Name.openConnectSheet` definition and all references.

**Invariant after fix.** No global notification is used for sheet presentation; sheet state lives on the window scene that owns it. Menu routing is focus-driven, so ⇧⌘K targets whichever window is key.

## Files touched

- `apps/Sources/Views/Sidebar/SidebarView.swift` — §1, §3
- `apps/Sources/ViewModels/SidebarModel.swift` — §1 (comment)
- `apps/Sources/CairnApp.swift` — §2 (menu items), §3 (menu routing)
- `apps/Sources/ContentView.swift` — §2 (no change; monitor stays), §3 (sheet binding, focused value publish)
- `apps/Sources/App/WindowSceneModel.swift` — §3 (connectSheetModel property)
- `apps/Sources/App/AppNotifications.swift` — §3 (remove openConnectSheet name)
- (Reuse the existing `FocusedValues.scene` key; no new focused value needed.)

## Verification

Build with `make build` (or Xcode), then:

1. **Recent removed.** Sidebar shows Favorites → Cloud → Remote Hosts → Locations. No Recent section regardless of history.
2. **Mouse nav.** ⌘[ and ⌘] navigate back/forward. Side button still works on mice that emit real mouse events (unchanged). Toolbar buttons still work.
3. **Per-window sheet.** Open two windows. Click "Connect…" in window A — sheet appears only in window A. Repeat with window B. Press ⇧⌘K — sheet opens in whichever window is key.
