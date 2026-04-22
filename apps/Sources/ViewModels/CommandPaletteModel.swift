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
