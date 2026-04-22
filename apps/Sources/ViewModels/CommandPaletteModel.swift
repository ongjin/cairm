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

    var isOpen: Bool = false
    var query: String = ""
    var selectedIndex: Int = 0

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
        query = ""
        selectedIndex = 0
        fileHits = []
        commandHits = []
        contentHits = []
        symbolHits = []
        contentSession?.cancel()
        contentSession = nil
    }

    func dispatch(tab: Tab, query raw: String, onCommand commands: [PaletteCommand]) {
        self.query = raw
        self.selectedIndex = 0
        let parsed = Self.parse(raw)

        switch parsed {
        case .fuzzy(let q):
            let indexed = tab.index?.queryFuzzy(q, limit: 50) ?? []
            // Only the bare-text fuzzy branch gets a fallback; @ / # / / / > all
            // require index-backed state (symbols, git, content, commands) that
            // can't be synthesised from FolderModel.
            fileHits = indexed.isEmpty ? fallbackFuzzyHits(folder: tab.folder) : indexed
            commandHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .command(let q):
            commandHits = commands.filter { q.isEmpty || $0.label.localizedCaseInsensitiveContains(q) }
            fileHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .content(let pat):
            contentSession?.cancel()
            contentHits = []
            if !pat.isEmpty, let s = tab.index?.startContent(pattern: pat) {
                contentSession = s
            }
            fileHits = []; commandHits = []; symbolHits = []
        case .gitDirty(let q):
            let dirty = tab.index?.queryGitDirty() ?? []
            fileHits = q.isEmpty ? dirty : dirty.filter { $0.pathRel.localizedCaseInsensitiveContains(q) }
            commandHits = []; contentHits = []; symbolHits = []
            contentSession?.cancel(); contentSession = nil
        case .symbol(let q):
            symbolHits = tab.index?.querySymbols(q, limit: 50) ?? []
            fileHits = []; commandHits = []; contentHits = []
            contentSession?.cancel(); contentSession = nil
        }
    }

    /// When IndexService is unavailable (e.g., ffi_index_open failed at
    /// Tab.rebuildServices time), fuzzy queries route here so the palette
    /// at least surfaces entries from the visible folder instead of going
    /// empty. Plain case-insensitive substring match — good enough for
    /// small folders, no Rust dependency on the sad path.
    func fallbackFuzzyHits(folder: FolderModel) -> [FileHit] {
        let raw = query.lowercased()
        guard !raw.isEmpty else { return [] }
        return folder.entries.compactMap { entry in
            let name = entry.name.toString().lowercased()
            return name.contains(raw)
                ? FileHit(pathRel: entry.name.toString(), score: 0)
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
