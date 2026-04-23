import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(WindowSceneModel.self) private var leftScene
    @Environment(WindowDualPaneModel.self) private var dualPane
    @Environment(\.cairnTheme) private var theme

    /// Active pane's current tab — used for toolbar-adjacent UI (title,
    /// search bar, palette). Menu/shortcut-driven mutations go through the
    /// `@FocusedValue(\.scene)` -> `dualPane.activePane` path.
    private var tab: Tab? { dualPane.activePane.activeTab }

    @State private var palette = CommandPaletteModel()
    /// Opaque token returned by `NSEvent.addLocalMonitorForEvents`. Held so we
    /// can remove the monitor on view teardown; losing it would leak the
    /// closure and keep dispatching events to a dead view.
    @State private var mouseNavMonitor: Any?

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(app: app)
            } detail: {
                detailColumn
            }
            .navigationTitle({
                guard let tab, let path = tab.currentPath else { return "Cairn" }
                if case .ssh(let target) = path.provider {
                    let name = path.lastComponent.isEmpty ? "/" : path.lastComponent
                    return "\(target.hostname) · \(name)"
                }
                return tab.currentFolder?.lastPathComponent ?? "Cairn"
            }())
            .toolbar { mainToolbar }
            .onChange(of: tab?.search.query) { _, _ in triggerSearchRefresh() }
            .onChange(of: tab?.search.scope) { _, _ in triggerSearchRefresh() }
            .onChange(of: tab?.folder.sortDescriptor) { _, _ in triggerSearchRefresh() }
            // Auto-collapse the split when the user closes the last tab in
            // the right pane — otherwise PaneColumn falls back to a lone
            // ProgressView / empty tab-strip which looks broken. Mirrors
            // Safari/Chrome's "closing the last tab closes the window"
            // convention, scoped to the right pane only.
            .onChange(of: dualPane.right?.tabs.isEmpty) { _, isEmpty in
                if isEmpty == true {
                    dualPane.toggleSplit(engine: app.engine, bookmarks: app.bookmarks, app: app)
                }
            }

            if palette.isOpen, let tab {
                CommandPaletteView(
                    model: palette,
                    tab: tab,
                    commands: builtinCommands(),
                    onActivate: handlePaletteActivate
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: palette.isOpen)
        .focusedSceneValue(\.paletteModel, palette)
        .focusedSceneValue(\.scene, dualPane.activePane)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard palette.isOpen else { return }
            if palette.mode == .content {
                palette.pollContent()
            }
        }
        .onAppear { installMouseNavMonitor() }
        .onDisappear { removeMouseNavMonitor() }
    }

    /// Detail column contents: one `PaneColumn` when single, two side-by-side
    /// when split. Each pane renders its own tab bar, inline
    /// back/forward/up/breadcrumb strip, and file list.
    @ViewBuilder
    private var detailColumn: some View {
        if let right = dualPane.right {
            HSplitView {
                PaneColumn(
                    scene: leftScene,
                    isActive: dualPane.activeSide == .left,
                    onFocus: { dualPane.focus(.left) }
                )
                PaneColumn(
                    scene: right,
                    isActive: dualPane.activeSide == .right,
                    onFocus: { dualPane.focus(.right) }
                )
            }
        } else {
            PaneColumn(
                scene: leftScene,
                isActive: true,
                onFocus: { dualPane.focus(.left) }
            )
        }
    }

    /// Mouse button 3 / 4 (the "Back" / "Forward" side buttons found on most
    /// external mice) route to the active pane's tab history. Wired via a
    /// local NSEvent monitor because NSView overrides only fire when the
    /// table is first responder — the user expects the side button to work
    /// everywhere in the window (breadcrumb, sidebar, preview pane, empty
    /// state).
    ///
    /// Button 3 is "back" on standard Mac mappings (Logitech, Razer, Apple's
    /// own USB Overdrive defaults). Button 4 is "forward". Returning the
    /// event unchanged for other buttons preserves middle-click and
    /// horizontal-wheel behaviour elsewhere; returning nil for 3/4 swallows
    /// it so it doesn't bubble to NSWindow as an unhandled click.
    private func installMouseNavMonitor() {
        guard mouseNavMonitor == nil else { return }
        mouseNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            switch event.buttonNumber {
            case 3:
                _ = tab?.goBack()
                return nil
            case 4:
                _ = tab?.goForward()
                return nil
            default:
                return event
            }
        }
    }

    private func removeMouseNavMonitor() {
        if let token = mouseNavMonitor {
            NSEvent.removeMonitor(token)
            mouseNavMonitor = nil
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            TransferHudChip(controller: app.transfers)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: toggleSplit) {
                Image(systemName: dualPane.isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
            }
            .help(dualPane.isSplit ? "Collapse Split View" : "Split View (⌘⇧D)")
            // Shortcut lives on the View menu entry so it doesn't double-fire.
        }
    }

    private func toggleSplit() {
        dualPane.toggleSplit(engine: app.engine, bookmarks: app.bookmarks, app: app)
    }

    private func builtinCommands() -> [PaletteCommand] {
        let scene = dualPane.activePane
        guard let tab = scene.activeTab else { return [] }
        return [
            PaletteCommand(id: "newTab", label: "New Tab", iconSF: "plus.square", shortcutHint: "⌘T") { scene.newTab() },
            PaletteCommand(id: "closeTab", label: "Close Tab", iconSF: "xmark.square", shortcutHint: "⌘W") {
                if let id = scene.activeTabID { scene.closeTab(id) }
            },
            PaletteCommand(id: "reload", label: "Reload", iconSF: "arrow.clockwise", shortcutHint: "⌘R") {
                if let p = tab.currentPath { Task { await tab.folder.load(p, via: tab.provider) } }
            },
            PaletteCommand(id: "toggleHidden", label: "Toggle Hidden Files", iconSF: "eye", shortcutHint: "⌘⇧.") {
                app.toggleShowHidden()
            },
            PaletteCommand(id: "pinFolder", label: "Pin Current Folder", iconSF: "pin", shortcutHint: "⌘D") {
                tab.toggleCurrentFolderPin()
            },
            PaletteCommand(id: "goUp", label: "Go to Parent Folder", iconSF: "arrow.up", shortcutHint: "⌘↑") {
                tab.goUp()
            },
        ]
    }

    private func handlePaletteActivate(_ data: PaletteRowData) {
        let tab = dualPane.activePane.activeTab
        switch data {
        case .file(let f):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(f.pathRel) ?? URL(fileURLWithPath: f.pathRel)
                openURL(url, tab: tab)
            }
        case .command(let c):
            c.run()
        case .content(let h):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(h.pathRel) ?? URL(fileURLWithPath: h.pathRel)
                openURL(url, tab: tab)
            }
        case .symbol(let s):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(s.pathRel) ?? URL(fileURLWithPath: s.pathRel)
                openURL(url, tab: tab)
            }
        }
        palette.close()
    }

    private func openURL(_ url: URL, tab: Tab) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func triggerSearchRefresh() {
        guard let tab else { return }
        tab.search.refresh(
            root: tab.currentFolder,
            showHidden: app.showHidden,
            sort: tab.folder.sortDescriptor,
            folderEntries: tab.folder.sortedEntries
        )
    }
}
