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

    /// Palette is owned by the parent `WindowScene` (see CairnApp.swift)
    /// so its `.focusedSceneValue(\.paletteModel, palette)` publishes at the
    /// same window-scope as `\.scene` — `@FocusedValue(\.paletteModel)`
    /// otherwise went nil when focus slid under SSH tab's view tree,
    /// disabling ⌘F / ⌘K on SSH tabs.
    let palette: CommandPaletteModel
    /// Opaque token returned by `NSEvent.addLocalMonitorForEvents`. Held so we
    /// can remove the monitor on view teardown; losing it would leak the
    /// closure and keep dispatching events to a dead view.
    @State private var historyInputMonitor: Any?
    @State private var historyInputRouter = HistoryNavigationInputRouter()

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
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard palette.isOpen else { return }
            if palette.mode == .content {
                palette.pollContent()
            }
        }
        .onAppear { installHistoryInputMonitor() }
        .onDisappear { removeHistoryInputMonitor() }
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

    /// History navigation from non-menu inputs. Some mice emit real side-button
    /// events; others have drivers that rewrite those buttons to ⌘← / ⌘→.
    private func installHistoryInputMonitor() {
        guard historyInputMonitor == nil else { return }

        let router = historyInputRouter
        let panes = dualPane
        historyInputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp, .keyDown]) { event in
            let routing: HistoryNavigationRouting
            switch event.type {
            case .otherMouseDown:
                routing = router.routeOtherMouseDown(buttonNumber: event.buttonNumber)
            case .otherMouseUp:
                routing = router.routeOtherMouseUp(buttonNumber: event.buttonNumber)
            case .keyDown:
                routing = HistoryNavigationInputRouter.routeKeyDown(keyCode: event.keyCode, modifiers: event.modifierFlags)
            default:
                routing = .passThrough
            }

            switch routing {
            case .passThrough:
                return event
            case .consume:
                return nil
            case .navigate(.back):
                _ = panes.activePane.activeTab?.goBack()
                return nil
            case .navigate(.forward):
                _ = panes.activePane.activeTab?.goForward()
                return nil
            }
        }
    }

    private func removeHistoryInputMonitor() {
        if let token = historyInputMonitor {
            NSEvent.removeMonitor(token)
            historyInputMonitor = nil
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
            root: tab.currentPath,
            provider: tab.provider,
            showHidden: app.showHidden,
            sort: tab.folder.sortDescriptor,
            folderEntries: tab.folder.sortedEntries
        )
    }
}
