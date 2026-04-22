import Foundation
import Observation

@Observable
final class CommandPaletteModel {
    enum ParsedQuery: Equatable {
        case fuzzy(String)
        case command(String)
        case content(String)
        case gitDirty(String)
        case symbol(String)
    }

    /// Source of truth for which result list is active. Was previously derived
    /// by sniffing `query.first`, but that scheme echoed the sigil into the
    /// TextField — confusing because the user couldn't tell whether `>` was
    /// being searched for or interpreted as a mode prefix. Now the sigil is
    /// consumed at input time and only renders as the leading chip.
    enum Mode: Equatable {
        case fuzzy, command, content, gitDirty, symbol

        init?(sigil: Character) {
            switch sigil {
            case ">": self = .command
            case "/": self = .content
            case "#": self = .gitDirty
            case "@": self = .symbol
            default: return nil
            }
        }

        var sigil: String {
            switch self {
            case .fuzzy:    return "›"
            case .command:  return ">"
            case .content:  return "/"
            case .gitDirty: return "#"
            case .symbol:   return "@"
            }
        }

        var placeholder: String {
            switch self {
            case .fuzzy:    return "Find files…"
            case .command:  return "Run command…"
            case .content:  return "Search file contents…"
            case .gitDirty: return "Filter dirty files…"
            case .symbol:   return "Jump to symbol…"
            }
        }
    }

    var isOpen: Bool = false
    var mode: Mode = .fuzzy
    var query: String = ""
    var selectedIndex: Int = 0
    /// Whether `/` (content) mode interprets the query as a regex. Default
    /// is literal because `*.tsx`-style patterns blow up under regex parsing
    /// and silently return zero hits, which reads as a bug to most users.
    /// The palette UI exposes a toggle when mode == .content.
    var contentIsRegex: Bool = false

    // Results — populated by mode-specific queries (Task 15).
    var fileHits: [FileHit] = []
    var commandHits: [PaletteCommand] = []
    var contentHits: [ContentHit] = []
    var symbolHits: [SymbolHit] = []

    var contentSession: ContentSearchSession?

    static func parse(_ raw: String) -> ParsedQuery {
        if raw.isEmpty { return .fuzzy("") }
        let first = raw.first!
        let rest = String(raw.dropFirst())
        switch first {
        case ">": return .command(rest)
        case "/": return .content(rest)
        case "#": return .gitDirty(rest)
        case "@": return .symbol(rest)
        default:  return .fuzzy(raw)
        }
    }

    func open(preFocusFuzzy: Bool = false) {
        isOpen = true
        if preFocusFuzzy, query.isEmpty {
            // Placeholder behavior differs for ⌘F vs ⌘K; internal state identical.
        }
    }

    func close() {
        isOpen = false
        mode = .fuzzy
        query = ""
        selectedIndex = 0
        fileHits = []
        commandHits = []
        contentHits = []
        symbolHits = []
        contentSession?.cancel()
        contentSession = nil
    }

    /// Called by the View whenever the TextField text changes. Intercepts a
    /// leading mode sigil (>, /, @, #) typed when the input is empty and the
    /// current mode is fuzzy: switches mode and discards the keystroke so it
    /// is not echoed in the field. Other input flows through unchanged.
    func setQuery(_ raw: String, tab: Tab, commands: [PaletteCommand]) {
        if mode == .fuzzy, raw.count == 1,
           let c = raw.first, let m = Mode(sigil: c) {
            mode = m
            query = ""
        } else {
            query = raw
        }
        runQuery(tab: tab, commands: commands)
    }

    /// Backspace from an empty input in a non-fuzzy mode reverts to fuzzy
    /// (the user is "exiting" the mode chip). Returns true when the keypress
    /// was consumed so the caller can stop event propagation.
    @discardableResult
    func tryConsumeBackspace(tab: Tab, commands: [PaletteCommand]) -> Bool {
        guard query.isEmpty, mode != .fuzzy else { return false }
        mode = .fuzzy
        runQuery(tab: tab, commands: commands)
        return true
    }

    /// Runs the query for `mode` + `query`. Always resets selection to 0 so
    /// keyboard nav starts at the top of the new result list.
    func runQuery(tab: Tab, commands: [PaletteCommand]) {
        selectedIndex = 0
        switch mode {
        case .fuzzy:
            if let idx = tab.index {
                fileHits = idx.queryFuzzy(query, limit: 50)
            } else {
                fileHits = fallbackFuzzyHits(folder: tab.folder, root: tab.currentFolder, query: query)
            }
            commandHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .command:
            commandHits = commands.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
            fileHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .content:
            contentSession?.cancel()
            contentHits = []
            if !query.isEmpty,
               let s = tab.index?.startContent(pattern: query, isRegex: contentIsRegex) {
                contentSession = s
            }
            fileHits = []; commandHits = []; symbolHits = []
        case .gitDirty:
            let dirty = tab.index?.queryGitDirty() ?? []
            fileHits = query.isEmpty ? dirty : dirty.filter { $0.pathRel.localizedCaseInsensitiveContains(query) }
            commandHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .symbol:
            symbolHits = tab.index?.querySymbols(query, limit: 50) ?? []
            fileHits = []; commandHits = []; contentHits = []
            contentSession?.cancel(); contentSession = nil
        }
    }

    /// Backward-compat shim for callers (and tests) that drive the model
    /// with a raw, sigil-prefixed string. New code should call `setQuery`
    /// so the sigil is consumed at the boundary instead.
    func dispatch(tab: Tab, query raw: String, onCommand commands: [PaletteCommand]) {
        setQuery(raw, tab: tab, commands: commands)
    }

    /// Used when `tab.index` is nil — typically the first ~hundreds of ms
    /// after a navigation while the Rust index walks the new root. Bounded
    /// recursive walk via `FileManager.enumerator` so subtree matches still
    /// surface; capped at `fallbackWalkLimit` entries to keep latency
    /// predictable on Home / large roots. Falls back to flat folder.entries
    /// if enumeration is unavailable. Once the real index arrives, the
    /// fuzzy branch stops calling this.
    static let fallbackWalkLimit = 2000

    func fallbackFuzzyHits(folder: FolderModel, root: URL?, query: String) -> [FileHit] {
        let raw = query.lowercased()
        guard !raw.isEmpty else { return [] }

        if let root,
           let enumerator = FileManager.default.enumerator(
               at: root,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            var hits: [FileHit] = []
            var seen = 0
            for case let url as URL in enumerator {
                seen += 1
                if seen > Self.fallbackWalkLimit { break }
                let name = url.lastPathComponent.lowercased()
                if name.contains(raw) {
                    let rel = url.path.hasPrefix(root.path + "/")
                        ? String(url.path.dropFirst(root.path.count + 1))
                        : url.lastPathComponent
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    hits.append(FileHit(pathRel: rel, score: 0, isDirectory: isDir))
                    if hits.count >= 50 { break }
                }
            }
            if !hits.isEmpty { return hits }
        }

        return folder.entries.compactMap { entry in
            let name = entry.name.toString().lowercased()
            return name.contains(raw)
                ? FileHit(pathRel: entry.name.toString(),
                          score: 0,
                          isDirectory: entry.kind == .Directory)
                : nil
        }
    }

    func pollContent() {
        guard let s = contentSession else { return }
        let new = s.poll(max: 20)
        contentHits.append(contentsOf: new)
    }
}

struct PaletteCommand: Identifiable, Hashable {
    let id: String
    let label: String
    let iconSF: String
    let shortcutHint: String?
    let run: () -> Void

    static func == (l: PaletteCommand, r: PaletteCommand) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
