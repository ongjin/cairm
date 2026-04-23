import SwiftUI

@main
struct CairnApp: App {
    @State private var app: AppModel

    init() {
        // T18: point the FFI content-search at the bundled ripgrep before any
        // AppModel side effect (IndexService, WindowSceneModel → Tab) spins up.
        if let rgURL = Bundle.main.url(forResource: "rg", withExtension: nil) {
            setenv("CAIRN_RG_PATH", rgURL.path, 1)
        }
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            WindowScene(app: app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // File > New Tab / Close Tab (slots after the default File > New).
            CommandGroup(after: .newItem) {
                TabFileMenuItems()
                ConnectFileMenuItems()
            }
            EditCommands()
            NavigateCommands()
            ViewCommands()
            FindCommands()
        }

        Settings {
            CairnSettingsView()
                .environment(app)
                .environment(\.cairnTheme, .glass)
        }
    }
}

/// Per-window wrapper. Owns a `WindowSceneModel` scoped to this scene and
/// injects it + `AppModel` into the environment for ContentView and friends.
///
/// Extracted in M1.8 T10 so each window gets its own `[Tab]`. When multi-window
/// lands in T11 a second WindowGroup scene will create an independent
/// WindowSceneModel with its own tab list; AppModel (engine, bookmarks, etc.)
/// stays shared across all windows.
struct WindowScene: View {
    let app: AppModel
    @State private var scene: WindowSceneModel

    init(app: AppModel) {
        self.app = app
        _scene = State(initialValue: WindowSceneModel(
            engine: app.engine,
            bookmarks: app.bookmarks,
            initialURL: app.bootstrapInitialURL()
        ))
    }

    var body: some View {
        ContentView()
            .environment(app)
            .environment(scene)
            .environment(\.cairnTheme, .glass)
            .frame(minWidth: 800, minHeight: 500)
            .background(VisualEffectBlur(material: .sidebar).ignoresSafeArea())
            // Publish this scene's models so `@FocusedValue`-reading
            // `CommandMenu`s can act on whichever window is frontmost.
            // T13: drives ⌘T/W/1-9/⌥←→, ⌘R, ⌘⇧., ⌘D.
            .focusedSceneValue(\.scene, scene)
            .focusedSceneValue(\.appModel, app)
            .focusedSceneValue(\.tabUndoManager, scene.activeTab?.undoManager)
    }
}

// MARK: - FocusedValue plumbing (T13)
//
// `@FocusedValue` lets a `CommandMenu` (which lives at `Scene`-level, outside
// any `View`) reach into the frontmost window's state. We publish both the
// `WindowSceneModel` and the shared `AppModel` so commands can mutate tab +
// app-global state without threading references through scene closures.

private struct FocusedSceneKey: FocusedValueKey { typealias Value = WindowSceneModel }
private struct FocusedAppKey: FocusedValueKey { typealias Value = AppModel }
struct FocusedPaletteKey: FocusedValueKey { typealias Value = CommandPaletteModel }
private struct FocusedUndoKey: FocusedValueKey { typealias Value = UndoManager }

extension FocusedValues {
    var scene: WindowSceneModel? {
        get { self[FocusedSceneKey.self] }
        set { self[FocusedSceneKey.self] = newValue }
    }
    var appModel: AppModel? {
        get { self[FocusedAppKey.self] }
        set { self[FocusedAppKey.self] = newValue }
    }
    var paletteModel: CommandPaletteModel? {
        get { self[FocusedPaletteKey.self] }
        set { self[FocusedPaletteKey.self] = newValue }
    }
    var tabUndoManager: UndoManager? {
        get { self[FocusedUndoKey.self] }
        set { self[FocusedUndoKey.self] = newValue }
    }
}

// MARK: - File > (New Tab / Close Tab)
//
// `CommandGroup(after: .newItem)` takes a `some View`, not `some Commands`,
// so these are plain Buttons grouped in a container View.

struct TabFileMenuItems: View {
    @FocusedValue(\.scene) private var scene: WindowSceneModel?

    var body: some View {
        Button("New Tab") {
            scene?.newTab()
        }
        .keyboardShortcut("t", modifiers: [.command])
        .disabled(scene == nil)

        Button("Close Tab") {
            guard let scene, let id = scene.activeTabID else { return }
            scene.closeTab(id)
        }
        .keyboardShortcut("w", modifiers: [.command])
        .disabled(scene == nil)
    }
}

// MARK: - File > Connect to Server (⇧⌘K)

struct ConnectFileMenuItems: View {
    var body: some View {
        Button("Connect to Server\u{2026}") {
            NotificationCenter.default.post(name: .openConnectSheet, object: nil)
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
    }
}

// MARK: - Navigate menu (tab switching)
//
// ⌘⌥← / ⌘⌥→ cycle tabs (the bare ⌘← / ⌘→ are already bound by the toolbar's
// back/forward buttons, hence the `.option` modifier here).
// ⌘1…⌘9 jumps to the Nth tab when it exists.

struct NavigateCommands: Commands {
    @FocusedValue(\.scene) private var scene: WindowSceneModel?

    var body: some Commands {
        CommandMenu("Navigate") {
            // ⌘↓ — Finder parity: descend into a selected folder, or open a
            // selected file in its default app. Companion to ⌘↑ (Go Up),
            // which is wired on the toolbar's parent-folder button.
            Button("Open Selected") { Self.openSelected(scene: scene) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(scene?.activeTab == nil)

            Divider()

            Button("Next Tab") { scene?.activateNext() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled((scene?.tabs.count ?? 0) < 2)
            Button("Previous Tab") { scene?.activatePrevious() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled((scene?.tabs.count ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { n in
                Button("Tab \(n)") { scene?.activateTab(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [.command])
                    .disabled((scene?.tabs.count ?? 0) < n)
            }
        }
    }

    /// Resolve the active tab's single-selection against its currently-visible
    /// entries (search-aware — uses `search.results` when a query is active,
    /// otherwise `folder.sortedEntries`). Directories navigate in-tab; files
    /// open via NSWorkspace like double-click. Beeps on empty or multi-select.
    private static func openSelected(scene: WindowSceneModel?) {
        guard let tab = scene?.activeTab else { return }
        let entries = tab.search.isActive ? tab.search.results : tab.folder.sortedEntries
        let matched = entries.filter { tab.folder.selection.contains($0.path.toString()) }
        guard matched.count == 1, let entry = matched.first else { NSSound.beep(); return }
        let url = URL(fileURLWithPath: entry.path.toString())
        if entry.kind == .Directory {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - View menu (reload / hidden files / pin current)
//
// T12 removed the pin / eye / reload toolbar buttons; this menu is their new
// home. Shortcuts: ⌘R, ⌘⇧., ⌘D.

struct ViewCommands: Commands {
    @FocusedValue(\.scene) private var scene: WindowSceneModel?
    @FocusedValue(\.appModel) private var app: AppModel?

    var body: some Commands {
        CommandMenu("View") {
            Button("Reload") {
                guard let tab = scene?.activeTab, let url = tab.currentFolder else { return }
                Task { await tab.folder.load(url) }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(scene?.activeTab?.currentFolder == nil)

            Button("Toggle Hidden Files") {
                app?.toggleShowHidden()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(app == nil)

            Button("Pin Current Folder") {
                scene?.activeTab?.toggleCurrentFolderPin()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(scene?.activeTab?.currentFolder == nil)
        }
    }
}

// MARK: - Find / Palette menu (⌘K / ⌘F)
//
// T15: `CommandPaletteView` is driven by a `CommandPaletteModel` published per
// window via `@FocusedValue(\.paletteModel)`. We slot after `.textEditing` so
// the default Find Next/Previous items remain available; the plain "Find…"
// here is bound to ⌘F and just opens the palette (optionally biased to fuzzy
// mode — the placeholder hint differs, not the state).

struct FindCommands: Commands {
    @FocusedValue(\.paletteModel) var palette: CommandPaletteModel?
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find\u{2026}") { palette?.open(preFocusFuzzy: true) }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(palette == nil)
            Button("Open Palette") { palette?.open() }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(palette == nil)
        }
    }
}

// MARK: - Edit > Undo / Redo (file-system mutations)
//
// SwiftUI's default `.undoRedo` group looks for an UndoManager on whatever
// view has focus, but our file list lives inside an NSViewRepresentable so
// the search misses. We replace the group with explicit buttons that read
// the active tab's UndoManager via `@FocusedValue`. Action names propagate
// through `setActionName` in the coordinator so the menu shows
// "Undo Move to Trash" / "Redo Move 3 Items" etc.

struct EditCommands: Commands {
    @FocusedValue(\.tabUndoManager) private var undoManager: UndoManager?

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(undoTitle) { undoManager?.undo() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!(undoManager?.canUndo ?? false))
            Button(redoTitle) { undoManager?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(undoManager?.canRedo ?? false))
        }
        CommandGroup(after: .pasteboard) {
            // Copy / Paste / Paste Item Here route through the responder chain.
            // `NSApp.sendAction(_:to:from:)` with `to: nil` walks first → last
            // responder; FileListNSTableView's overrides (Task 6) pick them up
            // when the table has focus.
            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command])

            Button("Paste Item Here") {
                NSApp.sendAction(#selector(CairnResponder.pasteItemHere(_:)),
                                 to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
        }
    }

    private var undoTitle: String {
        if let name = undoManager?.undoActionName, !name.isEmpty {
            return "Undo \(name)"
        }
        return "Undo"
    }
    private var redoTitle: String {
        if let name = undoManager?.redoActionName, !name.isEmpty {
            return "Redo \(name)"
        }
        return "Redo"
    }
}
